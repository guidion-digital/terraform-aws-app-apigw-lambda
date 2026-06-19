# In order to have invocations of this module re-usable across different instances,
# it is important that the following are variables.
#
# Their values are to come from elsewhere:
# - TFC workspaces get their values from TFC, whilst S3 (pseudo-TFC) workspaces
# - get theirs from a tfvars file in the configured S3 location for their backend
variable "application_name" {}
variable "domain_account_role" {}
variable "parent_zone" {}
variable "project" {}
variable "role_arn" {}
variable "stage" {}
variable "api_keys_share" {}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# NOTE: Both the dns_account_external and requester_external providers must be
#       set to us-east-1
provider "aws" {
  alias  = "dns_account"
  region = "us-east-1"

  assume_role {
    role_arn = var.domain_account_role
  }
}

provider "aws" {
  alias  = "requester"
  region = "us-east-1"
}

module "api-app-x" {
  source = "../../"

  providers = {
    aws.dns_account_external = aws.dns_account
    aws.requester_external   = aws.requester
  }

  application_name               = var.application_name
  namespace_supporting_resources = true
  stage                          = var.stage
  project                        = var.project
  domain_account_role            = var.domain_account_role
  parent_zone                    = var.parent_zone
  main_subdomain                 = "apoo"
  subdomains                     = ["foobar-coo"]
  parent_zone_in_domains         = false

  clients = {
    "unicorn-y" = {
      throttle_settings = {
        path        = "/"
        burst_limit = 200
      }
    }
  }

  api_keys_share = var.api_keys_share

  common_lambda_configuration = {
    "runtime"                        = "python3.8",
    "handler"                        = "vpctest.handler",
    "reserved_concurrent_executions" = 3,
    "memory_size"                    = 256,
  }

  global_method_configuration = {
    "logging_level"   = "ERROR",
    "metrics_enabled" = true,
  }

  # Map of the Lambdas to create, along with event sources
  lambdas = {
    "variable-test" = {
      handler      = "variable_test.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      "endpoints" = {
        "/variable-test" = {
          "get" = {
            security = []
          }
        }
      }

      environment = {
        "variable8" = "VALUE FOUND"
      }
    }

    # This is a dummy authoriser which will always succeed, and actually checks nothing
    "auth" = {
      "handler"    = "authorizer.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      # This will allow the Lambda to still be triggered from API GW. Usefule
      # for things like authorisers
      "allow_apigw_invocation" = true,
    }

    # Simple GET Lambda, protected by our dummy authoriser
    "get-without-vpc" = {
      handler           = "debug.handler",
      "source_dir"      = "${path.module}/dist/",
      "role_arn"        = var.role_arn,
      "publish_version" = false,

      "endpoints" = {
        "/lambda1" = {
          "get" = {
            security = ["api_key"]
          }
        }
      }
    }

    "get-without-vpc-2" = {
      handler      = "debug.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      "endpoints" = {
        "/lambda2" = {
          "get" = {
            security = ["api_key"]
          }
        }
      }
    }

    "get-without-vpc-3" = {
      handler      = "debug.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      "endpoints" = {
        "/lambda3" = {
          "get" = {
            security = ["api_key"]
          }
        }
      }
    }
  }

  authorizers = {
    # A custom authoriser to add to the API. The 'authorizer_uri' is constructed
    # from a combination of known values and the name of the authoriser Lambda
    custom = {
      "asm" = {
        name           = "Authorization",
        authorizer_uri = "arn:aws:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${var.application_name}-auth/invocations",
      }
    }
  }
}
