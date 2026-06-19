This Terraform module aims to be a 1:1 replacement for Serverless Framework. Although it is written in [HCL](https://github.com/hashicorp/hcl), you'll notice that many of the keys and values have direct relations to [Serverless](https://www.serverless.com/framework/docs) YAML, some even with the same key names.

# Rationale

This module brings up basic infrastructure for Lambdas. Right now, this includes:

- Web Application Firewall (optional)
- Lambdas
- API Gateway
- Route53 records (for the custom domain names)
- ACM certificates for above records
- VPC Transit Gateway relations (optional)
- SQS and Dynamo DB (optional)

# Usage

See [test_app](./examples/test_app/main.tf) for usage. Although efforts have been made to give all variables helpful descriptions and type definitions, descriptions can not be given to objects _inside_ those variables. Therefore it's useful to scan the docs below for usage guidelines.

## General Usage Notes

Here be dragons.

![Here be dragons](https://img.atlasobscura.com/pIFAHcCe_UseO9GpJ3wAqC_1eBEsYmH7dDcDaf2i4xo/rs:fill:12000:12000/q:81/sm:1/scp:1/ar:1/aHR0cHM6Ly9hdGxh/cy1kZXYuczMuYW1h/em9uYXdzLmNvbS91/cGxvYWRzL2Fzc2V0/cy9hNDcxMTI4MzIx/ZGJkNThjNDlfZHJh/Z29uLnBuZw.png)

### DNS

The module uses `domain_account_role` as an IAM role it can assume into, to create Route53 records for `parent_zone`, `subdomains`, and `main_subdomain` (more on that below).

The module is versatile, so it's easiest to summarise the possibilities in a list, where the first two are the recommended usage:

- Passing `subdomains` and `main_subdomain` will create all of those subdomains
- Passing `main_subdomain` will create only this subdomain
- Passing `parent_zone_in_domains` will always include `parent_zone` as a domain
- Passing `parent_zone` but neither `subdomains` nor `main_subdomain` will make `parent_zone` the only domain
- Passing `subdomains` will create all the subdomains in that list, and make the first one the main domain of the certificate

The ACM subdmodule includes the parent zone in the certificate by default. This can now be set to false, however in order to maintain backwards compatibility setting `parent_zone_in_domains = false` _in this module_ will still include the parent zone in the certificate if you set `DEPRECATED_acm_mode = true`.

Note that if you choose to set `parent_zone_in_domains` to true for _this_ module, your application will take ownership of the naked domain. For example, if your `parent_zone` is `guidion.com`, then this will be the only application to be able to use `guidion.com`. _You likely do not want to do this._

### Naming

Each key in `lambdas` is used throughout the module for naming resources, the Lambda names being the most obvious example.

The API Gateway resource will be called `application_name`, which will also be used together with `project` for naming and tagging.

### Lambda Configurations

The values given to `common_lambda_configuration` are given to all Lambdas, and overridden by values given in `lambdas{}`.

The following fields are supported by the common configuration block (`common_lambda_configuration`):

- function_name
- runtime
- handler
- environment
- reserved_concurrent_executions
- memory_size
- timeout
- environment

The following must be specified in the Lambda's own block (`lambdas{}`):

- event_triggers
- endpoints
- source_dir
- role_arn
- vpc_enabled (see below)
- vpc_config (see below)

`vpc_config` on the top level (outside of `lambdas{}`) — and setting the counter-part `lambdas{}.vpc_enabled` — is mutually exclusive with `lambdas{}.vpc_config`. The former is for when you wish this module to create a VPC for you, whilst the latter is for configuring Lambdas with an existing VPC.

> [!NOTE] `lambdas{}.environments` behaves a little differently, and is _concatenated_ with the default values from `common_lambda_configuration`.

#### Endpoints Configuration

Passing the optional `lambdas.{}.endpoints` map attaches an "http" event source to API Gateway. For the most part the examples are self explanatory, but the mapping of the same endpoint to different Lambdas bears explicit explanation.

A Lambda can only have a single handler. When we want to use a different Lambda for the same endpoint (but different verb), we create a new Lambda definition with that same endpoint:

```hcl
...

  # A Lambda with a single endpoint called '/something'
  lambdas {
    "lambda_for_gets" {
      handler = index.get_handler
      endpoints = {
        "/something" = {
          get = {}
        }
      }
    }

    # Another Lambda with the same endpoint, but different verb. Notice how
    # it's handler is different
    "lambda_for_puts" {
      handler = index.put_handler
      endpoints = {
        "/something" = {
          put = {}
        }
      }
    }
  }

...
```

A way of thinking about this is:

- A Lambda block defines a set of `endpoints{}.verbs`
- So if you need different `handler` for an `endpoint.verb`, you define a different Lambda block

You can of course have multiple endpoints and verbs in the same Lambda block, as long as they are happy pointing to the same handler:

```hcl

...

  lambdas {
    # A single Lambda, with multiple endpoints, and one endpoint with multiple
    # verbs
    "lambda_for_gets" {
      handler = index.get_handler
      endpoints = {
        "/something" = {
          get = {},
          put = {}
        },
        "/something-else" = {
          get = {}
        }
      }
    }

...
```

### Request Validators

The module comes with four pre-defined request validators: "all", "params-only", "body-only", and "none". This allows you to simply state which one you'd like to use in `lambdas{}.endpoints{}.request_validator`.

For convenience, you can specify one for all endpoints in all Lambdas by specifying it in `common_endpoint_configuration.request_validator`. You can then override this with the "none" version for methods that shouldn't be validated (such as mock `OPTIONS`).

### Responses

`lambdas{}.endpoints{}.responses` takes an [OAPI response object](https://swagger.io/specification/#responses-object). If `lambdas{}.endpoints{}.integration.type` is "mock", then this is also later mutated to create a valid [x-amazon-apigateway-integration.responses object](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-integration-responses.html), with the headers necessary to make the mock integration work.

For further convenience, mock `OPTIONS` integrations are populated with everything necessary, with only the list of methods needing to be specified in the `Access-Control-Allow-Headers` header (though you should see the #AccessControlAllowMethods(cheat-code) below for an easy way to do this).

It is still possible to override the integration response parameters both by passing an `lambdas{}.endpoints{}.responses` object, and by passing headers to `lambdas{}.endpoints{}.responses`.

Whilst you _can_ override the values filled in, bear in mind that supplying another
response code will override the default "200" we give, not add _another_ response

### AccessControlAllowMethods

Most of the time we only want to add integration response headers so that the `OPTIONS` methods for an endpoint work correctly with a mock integration. To make that task less tedious, there is a secret cheat code in the form of `lambdas{}.endpoints{}.AccessControlAllowMethods`. You can use this to pass all the endpoint's methods to be allowed, as in the example's `OPTIONS` method.

## Good-to-Knows and Caveats

### Secrets

The module can now create it's own secrets, and even specify principals for update operations (see [example](./examples/test_app/main.tf)). Bear in mind that in order for this to work, the secrets are namespaced. For example, if the secrets block looks like this:

```hcl
  secrets = {
    "ihaveaterrible" = {
      description    = "Secret for the foobar application"
      allowed_update = { "AWS" = ["arn:aws:iam::123456789012:role/sso/Superuser"] }
    }
```

Then a single secret will be created with the name `/applications/${application_name}/ihaveaterrible`. This means that when you want to reference that secret, you must use that name, and not just `ihaveaterrible`.

### Authorisers

Authorisers for the API Gateway can be defined in one of two ways:

1. Using this module: The Lambda can be defined along with the other Lambdas in the `var.lambdas{}` map with the `"allow_apigw_invocation" = true,`. It can then be added as a custom authoriser [in the `authorizers` block](https://github.com/guidion-digital/terraform-aws-app-api-lambda/blob/master/examples/simple/main.tf#L108).
2. Create an authorisation Lambda outside this module, and supply the `authorizer_uri` and `authorizer_credentials` fields for the custom authoriser block.

To assign an authoriser to a Lambda simply add/set the name of the authoriser in the `security` list, e.g. `security = ["custom_authorizer_name"]`.

### Deleting the ACM Certificate

> :warning: This seems to now be resolved, but leaving this note here since was ever changed and there are no updates about it that say so

Due to a [bug in AWS](https://stackoverflow.com/questions/69424636/unable-to-delete-aws-certificate-certificate-is-in-use), this module can not delete it's own ACM certificate. You will need to first delete the custom domain via the `--target` option, wait an unknown amount of time (average seems to be about an hour), then run destroy.

Not doing it in this order will leave your certificate un-deletable, and a support case needs to be raised to AWS to have it removed.

### A Note on Permissions

[This page](https://guidiondev.atlassian.net/wiki/spaces/DIG/pages/3929145345/Permissions+Architecture) details how permissions work, but essentially; when you tell Cinfra about a new application and it's permissions, an IAM role will be created holding those permissions. The application workspace will then come pre-prepared with a variable called `role_arn`, which you can use in your `lambdas{}.role_arn` definitions. See the [examples directory](./examples/full/) for usage.

If different permissions are required per Lambda, please provide a map of Lambda name to permission set, so that we can name the TFC variable holding the role ARN appropriately (since the name `role_arn` is already taken by the general permission set described above). For example, the permissions are for `lambda-x`, we would then call the variable `lambda-x_role_arn`.

### A Note on API 'Stages'

An API Gateway 'stage' can be thought of as a release environment, not to be confused with our own stages, which are completely separate AWS accounts. They are used to deploy pre-release versions of APIs, which you may wish to test on, send to certain clients for A/B testing, or canary.

We do not currently use them in this way, and rather use a single stage (within our own AWS stage environments) that we deploy to. For this reason, this module calls the stage 'live', since it is the single live stage that the API has, and any changes to it are immediately live.

### Merge or Overwrite?

[Hashicorp documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api) explains the predicament well:

> When importing Open API Specifications with the body argument, by default the API Gateway REST API will be replaced with the Open API Specification thus removing any existing methods, resources, integrations, or endpoints. Endpoint mutations are asynchronous operations, and race conditions with DNS are possible. To overcome this limitation, use the put_rest_api_mode attribute and set it to merge.

The issue with this, is that changes to endpoints and/or their methods can have non-intuitive results. For example, if a method is changed from `GET` to `POST`, the difference shown in the OpenAPI spec during a Terraform plan will show what you expect; `GET` will be deleted, and `POST` will be created. This might lead you believe that the `GET` method is going to be deleted, but what's actually going to happen is that this OpenAPI spec is going to be _merged_ with the existing one, which still has that method.

For this reason, we default to `overwrite`, but you can override this with the boolean `overwrite_stage`.

### Lambda Mapping Overwrites

It is possible that there may be a delay before AWS can give back accurate information on a Lambda trigger mapping. For example, when a Lambda is unmapped from an SQS queue, it is possible that AWS continues reporting that it is mapped.

This means that running Terraform again (during this time) would result in a false mapping conflict error. These instances usually last a few minutes, and shouldn't be encountered under normal usage.

### DynamoDB Table Index Change Considerations

In order to add or delete global secondary indexes, `dynamodb_tables{}.ignore_changes_global_secondary_index` must be set to `false` (this is it's default value). You can set it to `true` after the operation if you wish.

# Development

Development is done against [api-app-x](./examples/test_app).

That instance references the module with the local `../../` source value. For that to work with a pseudo-s3-workspace (or locally), you just need to be in the example folder. When using Terraform Cloud however, you will need to be in the root folder (this folder), and set your "Terraform Working Directory" to `./examples/test_app`.
