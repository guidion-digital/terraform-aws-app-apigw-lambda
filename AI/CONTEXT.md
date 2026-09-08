---
repo: terraform-aws-app-apigw-lambda
project_name: API Gateway + Lambda Application Module (Terrappy)
owner: Cinfra
domain: platform-infrastructure
criticality: high
summary: Reusable Terraform module that stands up a complete serverless HTTP application on AWS — Lambdas, an API Gateway REST API generated from an OpenAPI spec the module builds itself, custom domains with ACM certificates and Route53 records in a separate DNS account, plus optional WAF, VPC/Transit Gateway, DynamoDB, SQS, Secrets Manager, SSM parameters and ElastiCache. Intended as a 1:1 replacement for Serverless Framework.
main_stack:
  - Terraform / HCL
  - AWS (API Gateway v1 REST, Lambda, Route53, ACM, WAFv2, DynamoDB, SQS, Secrets Manager, SSM, ElastiCache, Transit Gateway)
  - Python (example Lambda handlers only)
  - GitHub Actions
  - Terraform Cloud / Enterprise
main_systems:
  - AWS API Gateway
  - AWS Lambda
  - Terraform Cloud / Enterprise
  - Terrappy (guidion-digital/terrappy)
  - Guidion DNS account (Route53)
  - Grafana / Loki (via promtail forwarder Lambda)
last_reviewed: 2026-09-07
review_confidence: low
generated_by: AI-assisted
validated_by: none
---

# API Gateway + Lambda Application Module (Terrappy)

## Overview

This repo is the Terraform module Guidion applications call to get a whole serverless HTTP API in one invocation. A consuming application declares its Lambdas and their HTTP endpoints in a single `lambdas{}` map; the module generates an OpenAPI 3.0.1 document from that map, hands it to `aws_api_gateway_rest_api` as the `body`, and wires up everything around it — custom domains, certificates, DNS in another AWS account, method-level throttling and logging, API keys, authorisers, WAF, and the supporting data stores the Lambdas need. It is deliberately shaped so that the HCL keys echo Serverless Framework YAML keys, to make migration off Serverless mechanical.

It is a **library, not a deployment**: nothing here runs in production on its own. `criticality: high` reflects that every consuming application's API deploy goes through this code, so a defect here lands in many applications at once — the repo owner should confirm or lower this.

- **Owner:** Cinfra — the cloud infrastructure team, `@guidion-digital/cinfra` in `.github/CODEOWNERS`, which assigns the whole repo to that one team
- **Main stack:** Terraform/HCL on AWS, with Python only in the example app's `dist/` handlers
- **Environment:** Consumer's AWS account and region for most resources; `us-east-1` is pinned for the `useast1`, `dns_account` and `requester` provider aliases (EDGE endpoints and ACM require it). The module's own CI exercises it in the Terraform Cloud workspace `constr-acc-apigw-app-x` against `examples/test_app`, under the `constr.acc.guidion.io` and `constr.dev.guidion.io` zones.

---

## Purpose and responsibilities

Does:

- Creates one `aws_api_gateway_rest_api` per application, named `var.application_name`, whose definition is an OpenAPI document the module builds by deep-merging each Lambda's `paths_spec` (`main.tf:373-377`, `407-435`)
- Creates one Lambda per key in `var.lambdas`, named `${application_name}-${key}` (`main.tf:100-144`), delegating the resource itself to `guidion-digital/helper-lambda/aws`
- Resolves per-Lambda configuration by overlaying `var.lambdas{}` onto `var.common_lambda_configuration`, except `environment`, which is _merged_ rather than overridden (`main.tf:109-112`)
- Builds the security schemes block for the OpenAPI spec from three authoriser flavours plus API keys (`main.tf:263-311`): authoriser Lambdas it creates itself, pre-existing custom authorisers referenced by URI, and Cognito user pools
- Grants API Gateway permission to invoke each Lambda, constructing `source_arn` by hand to break the API-Gateway-needs-Lambda-needs-API-Gateway cycle (`main.tf:211-236`)
- Creates the single API stage (`var.api_stage`, default `"live"`), its deployment, a global `*/*` method setting, and per-endpoint/per-verb method settings via `modules/method_settings`
- Creates custom domain names, base path mappings, and Route53 records — the records in a _different_ AWS account, reached by assuming `var.domain_account_role` (`dns.tf`)
- Creates CloudWatch log groups for the Lambdas itself, ahead of the promtail subscription filters that depend on them (`main.tf:561-580`)
- Optionally creates: a VPC with Transit Gateway attachment (from a Guidion fork of `terraform-aws-vpc`), a regional WAF ACL, DynamoDB tables, SQS queues, Secrets Manager secrets, SSM parameters, ElastiCache clusters, and per-client API keys
- Attaches event sources to Lambdas: SQS queues and CloudWatch schedule/pattern rules via `modules/event_triggers`, and DynamoDB streams directly in the root module

Does not do (delegated to):

- The Lambda, WAF, secret, SSM, API-key, authoriser, ACM and ElastiCache resources themselves → the eight `guidion-digital/helper-*` registry modules, and `cloudposse/label/null` for tags
- Networking primitives → the Guidion fork of `terraform-aws-vpc` at git ref `0.0.1`; the Transit Gateway itself is looked up, never created
- IAM roles and policies for the Lambdas → **Cinfra**, provisioned outside this repo and passed in as `var.lambdas{}.role_arn` (usually from a TFC workspace variable named `role_arn`; see the permissions note in `README.md`)
- Application code and its deployment packaging → the consuming application repo, which points `source_dir` at a directory
- State storage and plan/apply execution → Terraform Cloud / Enterprise, driven by reusable workflows in `guidion-digital/terrappy`
- Log storage and dashboards → Grafana/Loki, reached through an external promtail forwarder Lambda whose ARN is passed in
- API stages as release environments → nothing; Guidion uses one stage per AWS account, deliberately (see Architectural notes)

---

## Source of truth / data ownership

This module owns no business data. It _provisions_ stores and then steps back; the consuming application owns what goes into them. The distinction matters because destroying an application's workspace destroys the stores.

| Domain object / data                 | Source of truth                        | This system role                           | Notes                                                                                                                                                        |
| ------------------------------------ | -------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| API contract (OpenAPI document)      | This module                            | Owns / writes                              | Generated from `var.lambdas{}.endpoints`; `var.openapi_spec` lets a consumer supply a full document instead (`main.tf:337`)                                  |
| Lambda function code                 | Consuming application repo             | Displays / packages                        | Passed as `source_dir`; zipped by `helper-lambda`                                                                                                            |
| Lambda IAM permissions               | Cinfra (outside this repo)             | Reads                                      | Consumed as `role_arn`; the module never writes IAM roles for Lambdas                                                                                        |
| DynamoDB table contents              | Consuming application                  | Provisions, does not own                   | `var.dynamodb_tables` → `helper-supporting-resources`; names prefixed with `${application_name}-` when `namespace_supporting_resources = true` (the default) |
| SQS queue messages                   | Consuming application                  | Provisions, does not own                   | `var.sqs_queues`; same namespacing                                                                                                                           |
| Secret values                        | Whoever writes them at runtime         | Provisions envelope + resource policy only | Names are namespaced `applications/${application_name}/<key>` (`main.tf:68`) — reference the full path, not the bare key                                     |
| SSM parameter values                 | Whoever writes them at runtime         | Provisions                                 | Via `helper-ssm-parameters`; `ignore_changes` supports out-of-band values                                                                                    |
| ElastiCache cache contents           | Nothing (ephemeral)                    | Provisions                                 | Memcached by default                                                                                                                                         |
| DNS records for the app's subdomains | This module, in the DNS account        | Owns / writes                              | Assumes `var.domain_account_role`; the parent zone is only read (`dns.tf:109`)                                                                               |
| ACM certificate for those domains    | `helper-acm-validation`                | Provisions                                 | Validation records land in the DNS account, the certificate in the requesting account                                                                        |
| WAF ACL and IP sets                  | `helper-firewall`                      | Provisions                                 | Regional scope, attached to the API stage ARN                                                                                                                |
| VPC, subnets, TGW attachment         | Guidion `terraform-aws-vpc` fork       | Provisions (optional)                      | Only when `var.vpc_config` is set                                                                                                                            |
| Terraform state                      | Terraform Cloud / Enterprise workspace | Reads / consumes                           | Workspace `constr-acc-apigw-app-x` for this repo's own CI                                                                                                    |

---

## External integrations

| System                                            | Type                                  | Direction            | Notes                                                                                                                                                                                                            |
| ------------------------------------------------- | ------------------------------------- | -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Terraform Cloud / Enterprise                      | Terraform backend and run executor    | ↔ bidirectional      | Workspace `constr-acc-apigw-app-x` (`.github/workflows/test.yaml:28`, `release.yaml:22`); consumer workspaces supply `role_arn`, `parent_zone`, `domain_account_role`, `api_keys_share`, `vpc_cidr` as variables |
| `guidion-digital/terrappy`                        | Reusable GitHub Actions workflows     | → outbound           | `tfc-test-application-modules-plan-and-test-enterprise`, `…-apply-enterprise`, `tfc-destroy-enterprise`, all `@v2`. Terrappy is the framework this module is a member of                                         |
| `guidion-digital/release-workflows`               | Reusable GitHub Actions workflows     | → outbound           | PR test gate, tag dry-run, merge-into-master, release tag, all `@v2`                                                                                                                                             |
| Terraform Registry (`guidion-digital/helper-*`)   | Module registry                       | → outbound           | Eight helper modules; see APIs / services consumed                                                                                                                                                               |
| Terraform Registry (`cloudposse/label/null`)      | Module registry                       | → outbound           | Pinned `0.25.0`; produces the tag set                                                                                                                                                                            |
| `github.com/guidion-digital/terraform-aws-vpc`    | Git-sourced Terraform module          | → outbound           | Pinned to ref `0.0.1`; a Guidion fork carrying "fixes for the flow_logs bucket deprecations" (`main.tf:505`)                                                                                                     |
| AWS — application account                         | Cloud API                             | → outbound           | Default provider plus the `useast1` and `requester` aliases                                                                                                                                                      |
| AWS — DNS account                                 | Cloud API via `sts:AssumeRole`        | → outbound           | `aws.dns_account` / `aws.dns_account_external`, role from `var.domain_account_role`                                                                                                                              |
| AWS Transit Gateway (account-wide)                | Data source lookup                    | ← inbound dependency | `data "aws_ec2_transit_gateway" "this"` filtered only on `state = available` — unconditional, see Known risks                                                                                                    |
| AWS Cognito                                       | Authoriser                            | → outbound           | `var.authorizers.cognito{}.provider_arns`                                                                                                                                                                        |
| Grafana / Loki                                    | CloudWatch Logs subscription filter   | → outbound           | `var.grafana_promtail_lambda_arn`; the forwarder Lambda lives outside this module                                                                                                                                |
| `GuidionOps/infrastructure`                       | Terraform (TFC workspace definitions) | ← inbound            | The test app's workspace is defined at `projects/construction/acceptance/tfe-workspaces.tf` (`examples/test_app/main.tf:43-44`)                                                                                  |
| CherryBomb                                        | Local CLI linter, `local-exec`        | → outbound           | Optional (`var.validate_openapi_spec`), configured by `cherrybomb.json`; the binary must be on the runner                                                                                                        |
| Dependabot ← `app.terraform.io`                   | Dependency updates                    | ← inbound            | Daily, for `github-actions` and `terraform`; authenticated with the `TFC_PLANNER_API_TOKEN` secret                                                                                                               |
| `guidion-digital/context-layer`                   | Reusable GitHub Actions workflow      | → outbound           | `regenerate-context.yaml@0.0.20`, Mondays 05:00 UTC — rewrites this file from scratch. Steering lives in that workflow's `prompt_addition`                                                                       |
| tessl (`guidion-digital/terraform-modules` 0.0.8) | Vendored agent rules                  | ← inbound            | `tessl.json`; the vendored `.tessl/` tree is gitignored and absent — see AI assistant guidance                                                                                                                   |

Direction legend:

- `→ outbound`: this system calls another system
- `← inbound`: another system calls this system
- `↔ bidirectional`: both systems exchange data

---

## APIs exposed

The consumer-facing API of this repo is its **Terraform interface**, not HTTP. The inputs are `variables.tf` (25 variables; `stage`, `project`, `application_name`, `parent_zone`, `lambdas` and `common_lambda_configuration` are required). The outputs below are the contract other Terraform code depends on.

| Endpoint / method                                                                                                     | Purpose                                                                                     | Consumer                                |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------- |
| `output api_id`                                                                                                       | REST API id, e.g. for external `aws_lambda_permission` on a pre-created authoriser          | Consuming application root modules      |
| `output openapi_spec`                                                                                                 | The generated OpenAPI document                                                              | Consumers, spec publication, debugging  |
| `output openapi_spec_mocked`                                                                                          | Same document with `info` and a `servers` entry added, for the CherryBomb test only         | This repo's validator                   |
| `output lambdas` / `lambdas_local` / `lambda_arns`                                                                    | Full `helper-lambda` outputs, the computed spec map, and name→ARN                           | Consumers wiring further triggers       |
| `output dyanmodb_table_stream_arns`                                                                                   | Stream ARNs of created DynamoDB tables. **The typo is load-bearing** — see naming contracts | Consumers, and `main.tf:184` internally |
| `output secrets` / `secret_ids` / `secret_arns`                                                                       | Created secrets and their identifiers                                                       | Consumers granting access               |
| `output vpc_id` / `vpc_cidr` / `vpc_tgw_id` / `vpc_tgw_attachment_id`                                                 | Module-created VPC attributes, or the literal string `"none"`                               | Consumers, peering/routing              |
| `output method_settings`                                                                                              | Resolved per-method API Gateway settings                                                    | Debugging                               |
| `output subdomains`                                                                                                   | Echoes `var.subdomains` back                                                                | Consumers                               |
| `output elasticache_arn` / `_cache_nodes` / `_cluster_address` / `_configuration_endpoint` / `_engine_version_actual` | Intended to expose the created cluster. **Always `null`** — see Known risks                 | Consumers (currently broken)            |

The HTTP surface is declared by the consumer, not by this repo. `examples/test_app` exercises `GET /debug`, `GET /with-vpc`, `PUT /without-vpc`, `GET /without-vpc/{foo}`, `GET /sqs`, `GET /dynamodb`; `examples/simple` exercises `GET /variable-test`, `GET /lambda1`, `GET /lambda2`, `GET /lambda3`. Most are gated by the `api_key` security scheme, and `/debug` by the `asm` custom authoriser.

---

## APIs / services consumed

Versions below are the **constraints declared in tracked source**, not resolved versions. The repo's `.terraform.lock.hcl` is gitignored, so resolved versions are not a repo fact; a local untracked lockfile resolved the AWS provider into the 6.x line, and transitive helper-module constraints — not `versions.tf` — are what set the real floor.

| Service                                                     | Purpose                                                                                                           | Authentication                                               |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `guidion-digital/helper-lambda/aws` `~> 1.0`                | Creates each Lambda, its security groups/VPC config, and its OpenAPI `paths_spec`                                 | TFC-provided AWS credentials                                 |
| `guidion-digital/helper-supporting-resources/aws` `~> 3.0`  | DynamoDB tables and SQS queues, with optional namespacing                                                         | Same                                                         |
| `guidion-digital/helper-secrets/aws` `~> 1.0`               | Secrets Manager secrets and resource policies                                                                     | Same                                                         |
| `guidion-digital/helper-ssm-parameters/aws` `~> 0.0`        | SSM parameters (values default to `SecureString`)                                                                 | Same                                                         |
| `guidion-digital/helper-acm-validation/aws` `~> 2.0`        | ACM certificate plus cross-account validation records                                                             | Cross-account `sts:AssumeRole` via `var.domain_account_role` |
| `guidion-digital/helper-api-key/aws` `1.0.1` (exact)        | API Gateway keys, usage plans, throttling, cross-principal sharing                                                | Same                                                         |
| `guidion-digital/helper-api-authorizer/aws` `0.0.1` (exact) | A simple bearer-token authoriser Lambda, backed by a secret defaulting to `common/api-bearer-tokens`              | Same                                                         |
| `guidion-digital/helper-firewall/aws` `0.0.1` (exact)       | Regional WAFv2 web ACL, IP sets, managed rule groups                                                              | Same                                                         |
| `guidion-digital/helper-elasticache/aws` `~> 0.0`           | ElastiCache cluster and security groups. Creates no networking — a VPC and `vpc_id` must already exist            | Same                                                         |
| `cloudposse/label/null` `0.25.0` (exact)                    | Canonical tag set: `Terraform`, `Module=app-api-lambda`, `project`, `application`, `stage`                        | n/a                                                          |
| `guidion-digital/terraform-aws-vpc` git ref `0.0.1`         | VPC, private and transit-gateway subnets, TGW routes and flow logs                                                | Repo read access on the runner                               |
| `hashicorp/aws` provider `>= 2.7.0, < 7.0.0`                | All AWS resources; requires the two configuration aliases `aws.requester_external` and `aws.dns_account_external` | TFC workspace credentials                                    |
| `cloudposse/utils` `>= 0.3.0` (in `modules/deepmerge`)      | `utils_deep_merge_yaml` — merges per-Lambda path specs                                                            | n/a                                                          |
| CherryBomb                                                  | Optional OpenAPI lint via `local-exec`                                                                            | Binary must be installed on the runner                       |

---

## Deployment

**CI/CD:** GitHub Actions, delegating every real step to reusable workflows in `guidion-digital/terrappy` and `guidion-digital/release-workflows` (all pinned `@v2`).

**Infra:** Terraform on AWS, executed by Terraform Cloud / Enterprise. This repo is a module — consumers get it by `source`, and its own CI proves it by applying `examples/test_app`.

**Branch strategy:** `acc` is the default and integration branch (PRs target `acc`); a successful apply on `acc` merges into `master` and cuts a release tag. `master` is therefore the released state, `acc` the tested one. Note that this inverts the more common `main`-is-truth convention.

**Environments:**

- PR → `Test` workflow: plan and test in TFC workspace `constr-acc-apigw-app-x`, then a release-tag dry run
- Push to `acc` (or manual dispatch) → `Release` workflow: apply in the same workspace, then merge into `master` and tag. Two mutually-exclusive merge jobs distinguish "Terraform changed" from "only workflow files changed"
- Scheduled `Regenerate CONTEXT.md` workflow: Mondays at 05:00 UTC, calls `guidion-digital/context-layer` to regenerate `AI/CONTEXT.md` from scratch and open a PR. It reads `AI/LessonsLearned.md`; edits to this file that are not reflected in one of those two places will not survive the next run
- Scheduled `Destroy` workflow: Fridays at 20:00 UTC, tears down `examples/test_app` in both `dev` and `acc`, with a targeted certificate destroy first (the ACM ordering workaround described in the README)

---

## Architectural notes and key decisions

- **The OpenAPI document is the API.** Rather than `aws_api_gateway_resource` + `aws_api_gateway_method` per path, the module composes one OpenAPI document and passes it as `body`. This is what makes the Serverless-like `endpoints{}` map possible, and it is the root cause of several constraints below.
- **`put_rest_api_mode` defaults to `overwrite`, not `merge`.** `merge` produces plans that lie: changing `GET` to `POST` shows a delete-and-create, but the merge leaves the old method live. `overwrite` is honest at the cost of the race conditions HashiCorp warns about. Toggle with `var.overwrite_stage` (`variables.tf:466`).
- **`source_arn` for the Lambda invoke permission is string-built, not referenced.** Referencing the API Gateway resource would close a dependency cycle, so `main.tf:226-236` constructs `arn:aws:execute-api:…/*/*` from the region, account and API id. The long comment above it is the best explanation in the repo of why the OpenAPI approach forces this.
- **One API stage, always, called `live`.** API Gateway stages are release environments; Guidion uses whole AWS accounts for that instead, so the single stage is named for what it is. Canary and A/B use of stages is unimplemented by choice.
- **A Lambda block is a set of endpoint+verb pairs sharing one handler.** To serve the same path with a different handler per verb you declare a second Lambda with the same path and a different verb — the deep-merge combines them into one path object. This is the module's central idiom and the README documents it at length.
- **Cross-account DNS by assume-role.** Certificates are created in the application account; validation and application records in the DNS account. Two provider aliases (`aws.requester_external`, `aws.dns_account_external`) are _configuration aliases_, so every consumer must pass them — both pinned to `us-east-1`.
- **`parent_zone` and subdomains are handled by separate resources** because a record for the naked parent zone must be an A-alias while subdomains are CNAMEs (`dns.tf:41-48`, `:116-148`). Taking `parent_zone_in_domains = true` means the application claims the naked domain for the whole org; the README says loudly that you probably do not want this.
- **`DEPRECATED_acm_mode` is an intentional asymmetry.** It forces the parent zone into the _certificate_ (`dns.tf:33`) while leaving `parent_zone_in_domains` to decide whether a _domain name and record_ are created (`dns.tf:50`). That looks like a bug and is not: it is exactly the backwards-compatibility shim the README describes for instances deployed when the parent zone was the main ACM domain.
- **Secrets are namespaced, deliberately and invisibly.** A `secrets = { "foo" = … }` block yields a secret at `applications/${application_name}/foo`. Application code must use the full path; the test app shows this by passing the full path in an environment variable.
- **`aws_security_group.this` is a tombstone** (`main.tf:548-559`): kept only so that existing state can be migrated without a cyclical dependency, removable once every consumer has run the version that introduced the comment.
- **Development happens against a live example.** `examples/test_app` is the development target and CI subject, referencing the module as `../../`; the README explains the TFC "Terraform Working Directory" trick this requires.

---

## Known risks / fragile areas

**Broken now**

- **All five `elasticache_*` outputs are permanently `null`** (`outputs.tf:86-104`). They read `try(module.elasticache[0].…, null)`, but `module.elasticache` uses `for_each` over a map, so a numeric index never resolves and `try()` swallows the error. Verified against Terraform: the fallback always wins. `examples/test_app/main.tf:458` re-exports `elasticache_cluster_address`, so the example also reports `null`. Fix by indexing by key, e.g. `module.elasticache["memcached-01"]`, or by projecting the whole map.
- **`var.elasticache` without `var.vpc_config` fails the plan outright.** `memcached.tf:27-28` falls back to `module.vpc[0]` whenever a cluster's `vpc_id`/`subnet_ids` are unset. Verified: the conditional short-circuits when they _are_ set, but with both unset Terraform errors `Invalid index … module.vpc is empty tuple`. So ElastiCache requires either a module-created VPC or explicit `vpc_id` **and** `subnet_ids` on every cluster. (The equivalent fallback for Lambdas at `main.tf:126` is correctly guarded on `var.vpc_config == null`.)

**Dormant — fine today, breaks the moment something changes**

- **`var.acm_certificate_arn` is documented "NOT IN USE YET" but is wired as a count guard.** Setting it makes `module.acm_validations` count 0 (`dns.tf:20`), after which `one(module.acm_validations).all_subdomains` at `dns.tf:68` dereferences `null` and the plan fails. It is safe only because nobody sets it. Either finish it or make it fail loudly.
- **`local.waf_rules` and `local.managed_rules` (`variables.tf:468-565`, ~100 lines) are dead.** Nothing references them; `module.firewall` receives `var.firewall_configuration` whole. Byte-for-byte equivalents live in `helper-firewall`'s own `variables.tf`, so this is a leftover from moving the WAF logic into the helper — `default_ruleset_block_mode` works because the _helper_ implements it. Editing the copies here changes nothing.
- **Four `var.elasticache` fields are accepted and dropped.** `num_cache_nodes` and `allowed_security_groups` (`variables.tf:711`, `:723`) are declared but never passed to `module.elasticache`. A consumer asking for three cache nodes gets one, silently.
- **`var.metrics_enabled` (`variables.tf:38`) is declared and never read**, and `var.global_method_configuration` contributes only `logging_level` (`main.tf:463`) despite carrying nine fields. The variable description admits the second; nothing admits the first.
- **`versions.tf` understates its own floor.** It declares `>= 2.7.0, < 7.0.0`, but `main.tf:161` and both examples read `data.aws_region.current.region`, an attribute that only exists in recent AWS provider majors. It works because helper modules impose a much higher floor transitively. A consumer who pins low will get a confusing failure rather than a version conflict.

**Live constraints and sharp edges**

- **The Transit Gateway lookup is unconditional.** `data "aws_ec2_transit_gateway" "this"` (`main.tf:495`) has no `count` and filters only on `state = available`, so _every_ consumer — VPC or not — needs exactly one available TGW in the account. Zero or two both fail the plan.
- **CloudWatch log groups are created with no `retention_in_days`** (`main.tf:567`), so Lambda logs are retained forever, in every consuming application. Cost and data-minimisation both argue for setting this.
- **Two `aws_api_gateway_method_settings` resources manage the same stage.** `aws_api_gateway_method_settings.global` at `*/*` (`main.tf:457`) and the per-method resources in `modules/method_settings/method_settings_loop` both write stage-level settings; AWS models these as one mutable collection, which is a well-known source of perpetual diffs and last-writer-wins surprises.
- **Deep-merge round-trips through YAML.** `modules/deepmerge` encodes each map with `yamlencode`, merges via `utils_deep_merge_yaml`, and `yamldecode`s the result — so type fidelity depends on YAML, and `modules/deepmerge/versions.tf` still declares `template` and `http` providers it does not use.
- **Splitting one path across Lambdas breaks `AccessControlAllowMethods` inference.** `helper-lambda` documents in its own source that the auto-filled `Access-Control-Allow-Methods` only sees the methods of _one_ Lambda, so with a split path only the last-merged method survives. Set the `AccessControlAllowMethods` cheat-code field explicitly on split paths.
- **`aws_api_gateway_rest_api.body` is accepted-and-partly-ignored.** Only security-scheme resolution is validated in the generated document; `var.validate_openapi_spec` runs CherryBomb over a separately-built mock (`main.tf:339-351`) which may not match what AWS receives, and the linter itself has an open upstream bug.
- **ACM certificate deletion ordering.** The README's warning stands: destroy the custom domain with `--target` first, wait, then destroy — otherwise the certificate becomes undeletable without an AWS support case. The destroy workflow encodes this, imperfectly (see above).
- **SQS trigger mappings can report stale state.** Unmapping a Lambda from a queue can leave AWS reporting the old mapping for a few minutes, producing a false conflict on re-run.
- **DynamoDB triggers are capped at one table per Lambda** (`main.tf:171-191`), because the stream ARN is only knowable after `module.supporting_resources` runs and so cannot be pushed into `modules/event_triggers`. The code takes `keys(each.value)[0]`; a second table would be silently ignored.
- **The example handlers are demo-grade and should not be copied into production.** `dist/debug.py` returns the entire invocation event as the response body (it strips `x-api-key` but not `Authorization`); `dist/vpctest.py` opens a socket to any host and port given as query parameters; `dist/rdstest.py` is marked in its own header as unreviewed LLM output and interpolates a query parameter directly into SQL.

---

## AI assistant guidance

When modifying this repo:

- **Read `README.md` first.** It is unusually complete and carries the reasoning for most of the non-obvious behaviour — the endpoint/verb idiom, DNS combinations, mock `OPTIONS` handling, the `AccessControlAllowMethods` cheat code, merge-vs-overwrite, and the ACM deletion ordering. Do not re-derive these from the HCL.
- **Never rename anything in the naming contracts table below**, including the `dyanmodb` typo. These are cross-repo interfaces.
- Do not add `aws_api_gateway_resource` / `aws_api_gateway_method` resources. The API is defined by one generated OpenAPI document; adding per-path resources alongside a `body` fights the design.
- Do not create IAM roles or policies for Lambdas here. Permissions come from Cinfra as `role_arn`.
- Prefer extending a `guidion-digital/helper-*` module over adding resources to this root module — that is the Terrappy split, and duplicating helper logic here is exactly how `local.waf_rules` became dead code.
- Run `terraform fmt` and validate against `examples/test_app`, which is the intended development target. Be aware CI applies it for real, and the Friday destroy job will tear it down.
- **`agent-logs/`** holds concise per-task logs; follow the template in `agent-logs/README.md` for meaningful changes, and skip it for read-only exploration.
- **The agent-rules chain dangles.** `CLAUDE.md` includes `AGENTS.md`, which points at `.tessl/RULES.md` — but `.tessl/` is gitignored (`.gitignore`) and not present in a fresh clone, so there are no rules to follow at the end of that chain. It is regenerated by `tessl init`/`tessl install` from `tessl.json`. Do not treat the missing file as an error, and do not invent its contents.
- Treat the untracked `backend.tf` and `.terraform/` as local scaffolding, not repo facts: both are gitignored, and identifiers found there do not belong in documentation or commits.

If this file contradicts the actual code, the code wins — flag the discrepancy to the repo owner instead of trusting the doc

---

## Module interface and naming contracts

These strings are interfaces. Other repos, TFC workspaces, and deployed state depend on them by name, and renaming one breaks consumers with no compile-time error.

| Contract                                                              | Where it is defined                                                           | What depends on it                                                                                                                                      |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `output "dyanmodb_table_stream_arns"` — misspelled                    | `outputs.tf:51`, consumed at `main.tf:184` from `module.supporting_resources` | Both this module's output _and_ `helper-supporting-resources`' output carry the typo. Correcting the spelling is a breaking change in two repos at once |
| Lambda function name `${application_name}-${lambdas key}`             | `main.tf:102`                                                                 | CloudWatch log group names (`/aws/lambda/…`), event rule names, statement ids, and authoriser URIs consumers build by hand (`examples/*/main.tf`)       |
| Secret name `applications/${application_name}/<key>`                  | `main.tf:68`                                                                  | Application code reading the secret; IAM policies scoped to the path                                                                                    |
| Supporting-resource prefix `${application_name}-`                     | `var.namespace_supporting_resources` (default `true`)                         | Queue and table names the application code and `event_triggers.sqs_queues` refer to                                                                     |
| API stage name `live`                                                 | `var.api_stage` default (`variables.tf:21`)                                   | Base path mappings, method-setting paths, usage plan stage keys                                                                                         |
| REST API name `= var.application_name`                                | `main.tf:408`                                                                 | Console lookup and anything resolving the API by name                                                                                                   |
| Tag `Module = "app-api-lambda"`                                       | `main.tf:16`                                                                  | Cost allocation and inventory queries — and it does not match this repo's name                                                                          |
| TFC workspace `constr-acc-apigw-app-x`                                | `test.yaml:28`, `release.yaml:22`                                             | Defined in `GuidionOps/infrastructure`; renaming needs a change there too                                                                               |
| Provider aliases `aws.requester_external`, `aws.dns_account_external` | `versions.tf:6-9`                                                             | Configuration aliases — every consumer must pass both, in `us-east-1`                                                                                   |
| Request validator names `all`, `params-only`, `body-only`, `none`     | `var.request_validators` default                                              | Referenced by string from consumer `endpoints{}.request_validator`                                                                                      |
| TFC variable names `role_arn`, `<lambda-name>_role_arn`               | `README.md` permissions note                                                  | Cinfra provisions these into consumer workspaces                                                                                                        |

---

## Roadmap / active migrations

Drawn from in-repo `TODO`/`WIP` markers and `Development Notes.md`; none of these are dated or ticketed except where noted.

- [ ] Finish or remove `var.acm_certificate_arn` (bring-your-own certificate), currently a trap (`variables.tf:61`)
- [ ] Support `REGIONAL` and `PRIVATE` endpoint types properly; only `EDGE` is fully supported (`variables.tf:347`)
- [ ] Implement the rest of `var.global_method_configuration` beyond `logging_level` (`variables.tf:312`)
- [ ] `CI-175` — rework `var.api_keys_share` (`variables.tf:328`)
- [ ] Move the API stage deployment onto the documented `stage_description`/`stage_name` pattern (`main.tf:469-472`)
- [ ] Remove the backwards-compatibility `aws_security_group.this` once all consumers have applied the version that introduced its comment (`main.tf:548`)
- [ ] Rework `blocked_ips` from a flat list into a map of named IP sets with priorities, blocked today by not being able to delete an `aws_wafv2_ip_set` while a rule references it (`Development Notes.md`, and the commented-out block at `examples/test_app/main.tf:425-431`)
- [ ] Add `group_rules` (shared WAF rulesets provisioned centrally) — explicitly deferred until the infra repo publishes rulesets (`Development Notes.md`)
- [ ] Give supporting resources per-Lambda permissions, so one Lambda's access to a queue or table does not become every Lambda's (`Development Notes.md`)

---

## Freshness

- **Last reviewed:** 2026-09-07
- **Review confidence:** low
- **Generated by:** AI-assisted
- **Validated by:** none
- **Update when:** integrations change, stack changes, exposed APIs change, data ownership changes, or a relevant architectural decision is made

**Coverage of this generation.** Read in full: all 41 tracked files except `examples/simple/.gitignore` and `examples/test_app/.gitignore` — i.e. every root-module `.tf` file, all three local submodules, all three GitHub Actions workflows plus `dependabot.yml`, both examples and all five example Python handlers, `README.md`, `Development Notes.md`, `AGENTS.md`, `CLAUDE.md`, `CODEOWNERS`, `tessl.json`, `cherrybomb.json` and `agent-logs/README.md`. Characterised structurally, not read in full: the eleven external modules, whose READMEs, variable and output files were read from an untracked local `.terraform/` tree to establish interfaces only — their internals are not covered here. Four claims in Known risks were verified empirically against Terraform 1.6.1 in a scratch workspace rather than reasoned about: duplicate-object-key last-wins, `try()` over a `for_each` module indexed numerically, the count-0 module index inside a conditional, and that the same conditional short-circuits when its other branch is taken.

**Confidence is `low` because nothing here has been validated by a human**, not because the generation was shallow. Thoroughness of generation does not raise this field; only owner or tech-lead validation does.

**Provenance is unavailable.** Every `git log -S` probe for the suspicious strings in Known risks resolved to the single squashed commit `e0c210c` ("Initial commit"), so it is not possible to distinguish deliberate choices from imports for anything that predates it. Where this file says a behaviour is intentional, that judgement comes from `README.md` and code comments, not from history. The active branch at generation time was `context`; the default and integration branch is `acc`.
