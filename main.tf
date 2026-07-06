provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
}

module "these_tags" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  namespace = var.project
  name      = local.name
  delimiter = "-"

  tags = {
    "Terraform"   = "true",
    "Module"      = "app-api-lambda",
    "project"     = var.project,
    "application" = var.application_name,
    "stage"       = var.stage
  }
}

locals {
  secrets = { for this_secret, these_values in var.secrets : this_secret => {
    description                    = these_values.description
    kms_key_id                     = these_values.kms_key_id
    recovery_window_in_days        = these_values.recovery_window_in_days
    force_overwrite_replica_secret = these_values.force_overwrite_replica_secret
    rotation_configuration         = these_values.rotation_configuration

    policy = these_values.allowed_update != null ? jsonencode(
      {
        "Version" : "2012-10-17",
        "Statement" : [
          {
            "Effect" : "Allow",
            "Principal" : these_values.allowed_update,
            "Action" : [
              "secretsmanager:DescribeSecret",
              "secretsmanager:PutSecretValue",
              "secretsmanager:ListSecretVersionIds"
            ],
            "Resource" : "*"
          },
          {
            "Effect" : "Allow",
            "Principal" : these_values.allowed_update,
            "Action" : [
              "secretsmanager:GetRandomPassword",
              "secretsmanager:ListSecrets",
              "secretsmanager:BatchGetSecretValue"
            ],
            "Resource" : "*"
          }
        ]
    }) : null
    }
  }
}

module "secrets" {
  for_each = local.secrets

  source  = "guidion-digital/helper-secrets/aws"
  version = "~> 1.0"

  secrets = {
    "applications/${var.application_name}/${each.key}" = {
      description                    = each.value.description
      kms_key_id                     = each.value.kms_key_id
      policy                         = each.value.policy
      recovery_window_in_days        = each.value.recovery_window_in_days
      force_overwrite_replica_secret = each.value.force_overwrite_replica_secret
      rotation_configuration         = each.value.rotation_configuration
    }
  }

  tags = module.these_tags.tags
}

module "ssm_parameters" {
  source  = "guidion-digital/helper-ssm-parameters/aws"
  version = "~> 0.0"

  project          = var.project
  application_name = var.application_name
  stage            = var.stage

  parameters = var.ssm_parameters
}

locals {
  # Remove the 'Name' tag, because it's confusing when the resource name isn't
  # actually this
  tags = { for k, v in module.these_tags.tags : k => v if k != "Name" }

  # We want to set the function_name from the key of the local.lambdas item, but it
  # also needs to be unique, so we create a string from var.application_name and
  # the var.lambda{} item:
  lambdas = { for this_lambda_key, this_lambda_value in var.lambdas : this_lambda_key =>
    {
      function_name = "${var.application_name}-${this_lambda_key}",
      # N.B. runtime and handler _must_ be set by either common_lambda_configuration, or the lambda specification block
      runtime              = coalesce(this_lambda_value.runtime, var.common_lambda_configuration.runtime),
      handler              = coalesce(this_lambda_value.handler, var.common_lambda_configuration.handler),
      publish_version      = coalesce(this_lambda_value.publish_version, var.common_lambda_configuration.publish_version, true),
      latest_version_alias = coalesce(this_lambda_value.latest_version_alias, var.common_lambda_configuration.latest_version_alias, "live"),

      environment = (var.common_lambda_configuration.environment != null && this_lambda_value.environment == null) ? var.common_lambda_configuration.environment : merge(
        this_lambda_value.environment,
        var.common_lambda_configuration.environment
      ),

      reserved_concurrent_executions = (var.common_lambda_configuration.reserved_concurrent_executions != null && this_lambda_value.reserved_concurrent_executions == null) ? var.common_lambda_configuration.reserved_concurrent_executions : this_lambda_value.reserved_concurrent_executions,
      memory_size                    = (var.common_lambda_configuration.memory_size != null && this_lambda_value.memory_size == null) ? var.common_lambda_configuration.memory_size : this_lambda_value.memory_size,
      timeout                        = (var.common_lambda_configuration.timeout != null && this_lambda_value.timeout == null) ? var.common_lambda_configuration.timeout : this_lambda_value.timeout,
      event_triggers                 = this_lambda_value.event_triggers,
      common_endpoint_configuration  = var.common_endpoint_configuration,
      allow_apigw_invocation         = this_lambda_value.allow_apigw_invocation,
      endpoints                      = this_lambda_value.endpoints,
      source_dir                     = this_lambda_value.source_dir,
      role_arn                       = this_lambda_value.role_arn,
      security_group_rules           = this_lambda_value.security_group_rules,
      vpc_enabled                    = this_lambda_value.vpc_enabled,

      vpc_config = var.vpc_config == null || this_lambda_value.vpc_enabled == false ? this_lambda_value.vpc_config : {
        subnet_ids = [for _, value in module.vpc[0].private_subnet_attributes_by_az : value.id],
        vpc_id     = [module.vpc[0].vpc_attributes.id]
      }
    }
  }
}

module "api_lambdas" {
  source  = "guidion-digital/helper-lambda/aws"
  version = "~> 1.0"

  for_each = local.lambdas

  name             = each.key
  application_name = var.application_name
  specification    = each.value
  tags             = local.tags
}

module "supporting_resources" {
  source  = "guidion-digital/helper-supporting-resources/aws"
  version = "~> 3.0"

  namespacing_enabled = var.namespace_supporting_resources
  application_name    = var.application_name
  tags                = local.tags
  sqs_queues          = var.sqs_queues
  dynamodb_tables     = var.dynamodb_tables
}

locals {
  lambda_triggers = {
    for this_lambda, these_values in local.lambdas : this_lambda => {
      function_name = these_values.function_name
      sqs_triggers  = [for this_sqs in these_values.event_triggers.sqs_queues : "arn:aws:sqs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${this_sqs}"]
      # Note: This method can not work for DynamoDB because the stream ARN depends
      # on module.supporting_resources.dyanmodb_table_stream_arns[this_dynamodb]]
      # which can not be worked out before executing the sub-module
      # dynamodb_triggers   = [for this_dynamodb in these_values.event_triggers.dynamodb_tables : module.supporting_resources.dyanmodb_table_stream_arns[this_dynamodb]]
      cloudwatch_schedule = these_values.event_triggers.cloudwatch.schedule
      cloudwatch_pattern  = these_values.event_triggers.cloudwatch.pattern
    }
  }
}
resource "aws_lambda_event_source_mapping" "dynamodb_triggers" {
  depends_on = [module.api_lambdas, module.supporting_resources]

  for_each = {
    for lambda_name, lambda_config in local.lambdas : lambda_name => lambda_config.event_triggers.dynamodb_tables
    if length(lambda_config.event_triggers.dynamodb_tables) > 0
  }

  # NOTE: This works because there is only ever a single DynamoDB trigger
  # configured for a Lambda, so each.value[0] will always be the correct (only)
  # one. We can never have more than a single table trigger, because it is not
  # possible to move this into a sub-module like the module.event_triggers below.
  # There is a note above in local.lambda_triggers that explains further
  event_source_arn               = module.supporting_resources.dyanmodb_table_stream_arns[keys(each.value)[0]]
  function_name                  = local.lambdas[each.key].function_name
  enabled                        = true
  batch_size                     = [for this_table in each.value : this_table["batch_size"]][0]
  starting_position              = [for this_table in each.value : this_table["starting_position"]][0]
  maximum_retry_attempts         = [for this_table in each.value : this_table["maximum_retry_attempts"]][0]
  bisect_batch_on_function_error = [for this_table in each.value : this_table["bisect_batch_on_function_error"]][0]
}
module "event_triggers" {
  source = "./modules/event_triggers"

  depends_on = [module.api_lambdas, module.supporting_resources]

  for_each = local.lambda_triggers

  lambda_name         = each.key
  lambda_arn          = module.api_lambdas[each.key].lambda_arn
  function_name       = each.value.function_name
  sqs_triggers        = each.value.sqs_triggers
  cloudwatch_schedule = each.value.cloudwatch_schedule
  cloudwatch_pattern  = each.value.cloudwatch_pattern
  tags                = local.tags
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Since the creation of aws_api_gateway_rest_api.this is done with a constructed
# OpenAPI spec via the 'body' argument, we need to know the ARNs of the Lambdas
# (which must be present in that spec as part of the 'x-amazon-apigateway-integration' block).
#
# If we tried to create the aws_lambda_permission below in module.api_lambdas, the
# value for source_arn couldn't be provided, since it depends on the API Gateway
# being created, which relies on the Lambda being created, which ... ;)
#
# This isn't a problem if using aws_api_gateway_resource and aws_api_gateway_method
# to create API resources, but those require splitting up the paths into individual
# resources.
#
# We get around the chicken-and-egg instead, by constructing the value for
# source_arn here instead, since we know exactly what it will be, given the API
# Gateway resource, and the Lambda resource
resource "aws_lambda_permission" "this" {
  for_each = { for this_lambda, this_spec in local.lambdas : this_lambda => this_spec if length(this_spec.endpoints) != 0 || this_spec.allow_apigw_invocation }

  statement_id  = "${var.application_name}-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  qualifier     = each.value.publish_version ? each.value.latest_version_alias : null
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.id}:${aws_api_gateway_rest_api.this.id}/*/*"
}

module "api_keys" {
  for_each = var.clients

  source  = "guidion-digital/helper-api-key/aws"
  version = "1.0.1"

  name              = "${var.application_name}/${each.key}"
  principals        = var.api_keys_share
  api_id            = aws_api_gateway_rest_api.this.id
  stages            = { (aws_api_gateway_stage.this.stage_name) = {} }
  throttle_settings = each.value.throttle_settings
  tags              = local.tags
}

module "authorizer" {
  for_each = var.authorizers.create_custom

  source  = "guidion-digital/helper-api-authorizer/aws"
  version = "0.0.1"

  name        = each.key
  secret_name = each.value.secret_name
  tags        = local.tags
}

locals {
  created_custom_authorizers = { for this_authorizer, these_configs in module.authorizer : this_authorizer => {
    "name"                         = "Authorization",
    "type"                         = "apiKey",
    "in"                           = "header",
    "x-amazon-apigateway-authtype" = "custom",
    "x-amazon-apigateway-authorizer" = {
      "type"                         = "token"
      "authorizerUri"                = these_configs.lambda_invoke_arn,
      "authorizerResultTtlInSeconds" = "300"
    }
    }
  }

  custom_authorizers = { for this_authorizer, these_configs in var.authorizers.custom : this_authorizer => {
    "name"                         = these_configs.name,
    "type"                         = these_configs.type,
    "in"                           = these_configs.in,
    "x-amazon-apigateway-authtype" = "custom",
    "x-amazon-apigateway-authorizer" = {
      "type"          = "token",
      "authorizerUri" = these_configs.authorizer_uri,
      "authorizerCredentials" : these_configs.authorizer_credentials,
      "authorizerResultTtlInSeconds" = these_configs.authorizer_ttl
    }
    }
  }

  cognito_authorizers = { for this_authorizer, these_configs in var.authorizers.cognito : this_authorizer => {
    "name"                         = these_configs.name,
    "type"                         = these_configs.type,
    "in"                           = these_configs.in,
    "x-amazon-apigateway-authtype" = "custom",
    "x-amazon-apigateway-authorizer" = {
      "type"         = "cognito_user_pools",
      "providerARNs" = these_configs.provider_arns
    }
    }
  }

  api_key = length(var.clients) != 0 ? {
    api_key = {
      "type" = "apiKey",
      "name" = "x-api-key",
      "in"   = "header"
    }
  } : {}

  securitySchemes = merge(local.created_custom_authorizers, local.custom_authorizers, local.cognito_authorizers, local.api_key)
  components = {
    securitySchemes = local.securitySchemes
  }

  # Create one of these:
  # https://github.com/OAI/OpenAPI-Specification/blob/main/versions/3.0.1.md
  openapi_spec_generated = jsonencode({
    openapi                                = "3.0.1"
    paths                                  = module.paths_spec.merged
    components                             = local.components
    x-amazon-apigateway-request-validators = var.request_validators
  })

  # TODO: Ensure that `body` is validated somehow. Its seems that this resource
  #       accepts and ignores invalid _parts_ of the body, meaning we could end
  #       up in a situation other than what we think we've specified. For example,
  #       if the 'security' key for an endpoint is malformed, there would be no
  #       security on the endpoint, even though we think we're said there should be
  #
  #       Possible solutions:
  #       1. Validate the parts of the schema we use with pre and post conditions:
  #          - https://developer.hashicorp.com/terraform/tutorials/configuration-language/custom-conditions#add-preconditions
  #          - https://developer.hashicorp.com/terraform/tutorials/configuration-language/custom-conditions#add-a-postcondition
  #       2. Use something like CherryBomb at deploy-time on an outputted file:
  #          - https://github.com/blst-security/cherrybomb
  openapi_spec = var.openapi_spec != null ? var.openapi_spec : local.openapi_spec_generated

  full_openapi_spec_mocked = jsonencode({
    "openapi" = "3.0.1"
    "info" : {
      "title" : var.application_name,
      "version" : "2023-09-28T17:11:53Z"
    },
    "servers" : [
      # This is only for the validator test
      { "url" : "https://api-app-x.constr.dev.guidion.io" }
    ],
    paths      = jsondecode(local.openapi_spec).paths
    components = jsondecode(local.openapi_spec).components
  })
}

# WIP: There seems to be a bug in the linter:
# https://github.com/blst-security/cherrybomb/issues/140
#
# This also shouldn't be relied on until a we're happy with the way local.full_openapi_spec_mocked
# is generated, since it is currently constructed separately, and potentially not
# the same as what the aws_rest_api produces
resource "null_resource" "validator" {
  count = var.validate_openapi_spec == true ? 1 : 0

  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "cherrybomb --file <(echo '${local.full_openapi_spec_mocked}')"
  }
}

module "paths_spec" {
  source = "./modules/deepmerge"

  maps = [for this_one in module.api_lambdas : this_one.paths_spec]
}

resource "aws_api_gateway_rest_api" "this" {
  name              = var.application_name
  put_rest_api_mode = local.put_rest_api_mode
  tags              = local.tags

  endpoint_configuration {
    types = var.endpoint_types
  }

  body = local.openapi_spec
}

# Remap Lambda endpoints and send them to module.method_settings to have their
# settings set
module "lambdas" {
  source = "./modules/deepmerge"

  maps = [for this_one in var.lambdas : this_one["endpoints"]]
}
locals {
  endpoints_with_settings_merged = {
    for this_lambda, these_endpoints in module.lambdas.merged : this_lambda => these_endpoints
  }
}
module "method_settings" {
  source = "./modules/method_settings"

  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  endpoints   = local.endpoints_with_settings_merged
}

resource "aws_api_gateway_method_settings" "global" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    logging_level = var.global_method_configuration.logging_level
  }
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  # TODO
  # https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-deploy-api.html
  # stage_name        = var.api_stage
  # stage_description = sha1(jsonencode(aws_api_gateway_rest_api.this.body))

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.this.body))

    lambda_versions = sha1(jsonencode({
      for k, v in module.api_lambdas : k => v.lambda_version
    }))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  stage_name = var.api_stage

  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  tags          = local.tags
}

data "aws_ec2_transit_gateway" "this" {
  filter {
    name   = "state"
    values = ["available"]
  }
}

module "vpc" {
  count = var.vpc_config != null ? 1 : 0

  # Using our fork of this module with fixes for the flow_logs bucket deprecations
  source = "git::https://github.com/guidion-digital/terraform-aws-vpc.git?ref=0.0.1"

  name               = local.name
  cidr_block         = var.vpc_config.vpc_cidr
  az_count           = var.vpc_config.az_count
  transit_gateway_id = data.aws_ec2_transit_gateway.this.id
  tags               = local.tags

  transit_gateway_routes = {
    private = "0.0.0.0/0"
  }

  subnets = {
    private = {
      netmask = 26
    }

    transit_gateway = {
      netmask                                         = 28
      transit_gateway_default_route_table_association = true
      transit_gateway_default_route_table_propagation = true
      transit_gateway_appliance_mode_support          = "disable"
      transit_gateway_dns_support                     = "disable"
    }

  }
}

module "firewall" {
  count      = var.firewall_configuration != null ? 1 : 0
  depends_on = [aws_api_gateway_stage.this]

  source  = "guidion-digital/helper-firewall/aws"
  version = "0.0.1"

  scope                  = "REGIONAL"
  application_name       = "${var.application_name}-regional"
  resource_arn           = aws_api_gateway_stage.this.arn
  firewall_configuration = var.firewall_configuration
  tags                   = local.tags
}

# TODO: This is only here for the sake of backwards compatiblity. Removal before
#       running the new version results in a cyclical dependancy loop.
#
#       It can be removed once the version of the module in which this comment first
#       appears has been run
resource "aws_security_group" "this" {
  count = var.vpc_config == null ? 0 : 1

  name   = local.name
  vpc_id = module.vpc[0].vpc_attributes.id
  tags   = local.tags
}

# We create log groups for the Lambdas ourselves, since they need to exist
# immediately, else the subscription filter resource below will fail
locals {
  lambda_log_groups = [for this_lambda, these_values in local.lambdas : "/aws/lambda/${these_values.function_name}"]
}

resource "aws_cloudwatch_log_group" "lambdas" {
  for_each = toset(local.lambda_log_groups)

  name = each.value
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_promtail_logfilter" {
  for_each = var.grafana_promtail_lambda_arn != null ? aws_cloudwatch_log_group.lambdas : {}

  name            = "lambda_promtail_logfilter_${each.value.name}"
  log_group_name  = each.value.name
  destination_arn = var.grafana_promtail_lambda_arn
  filter_pattern  = ""
}
