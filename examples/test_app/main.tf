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
variable "vpc_cidr" {}

# These are example values used below for naming. They are here for consistancy
# and ease of use. You do not need these exact names of values for local variables
locals {
  dynamodb_events_table         = "events"
  dynamodb_errored_events_table = "errored-events"
  sqs_processed_queue           = "processed"
}

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

# Uses the workspace created here:
# https://github.com/GuidionOps/infrastructure/blob/main/projects/construction/acceptance/tfe-workspaces.tf
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
  main_subdomain                 = "coocoo"
  subdomains                     = ["foobar"]
  parent_zone_in_domains         = false

  clients = { "unicorn-x" = {
    throttle_settings = {
      path        = "/"
      burst_limit = 200
    }
  } }

  api_keys_share = var.api_keys_share

  vpc_config = {
    vpc_cidr = var.vpc_cidr
  }

  secrets = {
    "ihaveaterrible" = {
      description             = "secret"
      recovery_window_in_days = 0

      # The map of principals passed here will be allowed to write values for
      # this secret
      allowed_update = {
        # Allow writes from the EC2 service in entirety
        "Service" = [
          "ec2.amazonaws.com"
        ],
        # Allow a role write operations. The role itself will _not_ need
        # any permissions to perform actions on this secret.
        "AWS" = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sso/Read-Only"
        ]
      }

      # Requires a real Lambda to run, which is outside the scope of this test
      # rotation_configuration = {
      #   lambda_arn          = "arn:aws:lambda:eu-central-1:123456789012:function:you-secret-rotator"
      #   schedule_expression = "rate(1 day)"
      # }
    }
  }

  dynamodb_tables = {
    (local.dynamodb_events_table) = {
      attributes = [
        { name = "id", type = "N" },
        { name = "createdAt", type = "S" },
        { name = "gsi1", type = "N" }
      ],
      hash_key  = "id",
      range_key = "createdAt",

      global_secondary_indexes = [
        {
          name               = "createdAtIndex",
          hash_key           = "createdAt",
          range_key          = "gsi1",
          non_key_attributes = ["id"],
          autoscaling = {
            read_max_capacity = 25
          }
        }
      ]

      ttl_attribute_name = "expiresAt",
    }
  }

  sqs_queues = {
    (local.sqs_processed_queue) = {
      # Override configuration here
      #
      # e.g.:
      # delay_seconds = 10
      #
      # This one will actually also create the necessary policy to enable rw on
      # the ARNs specified, and attach it
      # "readwrite_arns" = ["arn:aws:iam::123456789012:role/application/app-x"]
    }
  }

  elasticache = {
    "memcached-01" = {
      application_name = var.application_name
      project          = var.project
      stage            = var.stage
      engine           = "memcached"
      engine_version   = "1.6.17"
      node_type        = "cache.t3.micro"
      az_mode          = "single-az"
    }
  }

  common_lambda_configuration = {
    "runtime"                        = "python3.8",
    "handler"                        = "vpctest.handler",
    "reserved_concurrent_executions" = 3,
    "memory_size"                    = 256
  }

  global_method_configuration = {
    "logging_level"   = "ERROR",
    "metrics_enabled" = true,
  }

  # Map of the Lambdas to create, along with event sources
  lambdas = {
    # A standalone Lambda with no event triggers
    "standalone" = {
      "handler"    = "debug.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      # This will allow the Lambda to still be triggered from API GW. Usefule
      # for things like authorisers
      "allow_apigw_invocation" = true,

      # A single environment variable is given to the Lambda containing the name
      # of the AWS Secrets Manager secret we defined above. N.B. that it must be
      # namespaced with "applications/${var.application_name}/" as below
      "environment" = {
        secret_name = "applications/${var.application_name}/ihaveaterrible"
      }
    }

    # A Lambda triggered by a time event
    "timed" = {
      "handler"    = "debug.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      "event_triggers" = {
        cloudwatch = {
          "schedule" = "cron(50 * * * ? *)"
        }
      }
    }

    # Lambda with a VPC enabled, showing how security groups can be configured
    "get-with-vpc" = {
      "vpc_enabled" = true,
      "handler"     = "vpctest.handler",
      "source_dir"  = "${path.module}/dist/",
      "role_arn"    = var.role_arn,

      "security_group_rules" = {
        ingress = {
          "https" = {
            protocol  = "tcp",
            from_port = 443,
            to_port   = 443,
            cidr      = "0.0.0.0/0"
          },
          "http" = {
            protocol  = "tcp",
            from_port = 80,
            to_port   = 80,
            cidr      = "0.0.0.0/0"
          }
        }
      },

      "endpoints" = {
        "/with-vpc" = {
          "get" = {
            security = ["api_key"]
          }
        }
      }
    },

    # A Lambda with an http trigger, specified by the `endpoints` key
    "get-without-vpc" = {
      handler      = "vpctest.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      "endpoints" = {
        "/without-vpc" = {
          "get" = {
            security = ["api_key"]
          }
        }
      }
    },

    # Lambda inside a pre-existing VPC
    # The subnet and security group fixtures does not exist, but this is what it would look like
    #     "get-with-existing-vpc" = {
    #       "handler"    = "vpctest.handler",
    #       "source_dir" = "${path.module}/dist/",
    #       "role_arn"   = var.role_arn,
    #
    #       vpc_config = {
    #         subnet_ids         = [[for _, value in module.shared_resources.vpc[0].private_subnet_attributes_by_az : value.id]],
    #         security_group_ids = ["sg-000000000000"]
    #       }
    #
    #       "endpoints" = {
    #         "/with-existing-vpc" = {
    #           "get" = {
    #             security = ["api_key"]
    #           }
    #         }
    #       }
    #     },

    # Same endpoint as above, but for PUT
    "put-without-vpc" = {
      handler      = "debug.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      "endpoints" = {
        "/without-vpc" = {
          "put" = {
            security = ["api_key"]

            # This would turn off all security — including the enabled by default
            # api_key schema
            #
            # "security" = []
          }
        }
      }
    },

    # Another Lambda with a http trigger, specified by the `endpoints` key
    "path-parameter" = {
      "handler"    = "vpctest.handler"
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      "endpoints" = {
        "/without-vpc/{foo}" = {
          "get" = {
            security = ["api_key"],

            "parameters" = {
              "beepboop" = {
                "required" = false,
                "in"       = "path",
                "schema" = {
                  "type" = "string"
                }
              }
            }
          }
        }
      }
    },

    # Lambda is only triggered by an SQS event
    "sqs-trigger" = {
      "source_dir" = "${path.module}/dist/",
      "handler"    = "debug.handler",
      "role_arn"   = var.role_arn,

      "event_triggers" = {
        "sqs_queues" = ["${var.application_name}-${local.sqs_processed_queue}"]
      }
    },

    # Lambda is only triggered via it's HTTP endpoint (/sqs)
    "get-with-sqs" = {
      "source_dir" = "${path.module}/dist/",
      "handler"    = "sqstest.handler",
      "role_arn"   = var.role_arn,

      "endpoints" = {
        "/sqs" = {
          "get" = {
            security = ["api_key"],

            "parameters" = {
              "queue-name" = {}
            }
          }
        }
      }
    },

    # Lambda is only triggered by a DynamoDB stream
    "with-dynamo" = {
      "handler"     = "debug.handler",
      "source_dir"  = "${path.module}/dist/",
      "role_arn"    = var.role_arn,
      "vpc_enabled" = false,
      "memory_size" = 128

      "event_triggers" = {
        "dynamodb_tables" = {
          "${var.application_name}-${local.dynamodb_events_table}" = {
            "maximum_retry_attempts" = 5
          }
        }
      }
    }

    # Lambda is only triggered via it's HTTP endpoint (/dynamodb)
    "get-with-dynamodb" = {
      "handler"     = "dynamotest.handler",
      "source_dir"  = "${path.module}/dist/",
      "role_arn"    = var.role_arn,
      "vpc_enabled" = false,
      "memory_size" = 128

      "endpoints" = {
        "/dynamodb" = {
          "get" = {
            security = ["api_key"],

            "parameters" = {
              "id"         = {},
              "bar"        = {},
              "table-name" = {}
            }
          }
        }
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
      handler      = "debug.handler",
      "source_dir" = "${path.module}/dist/",
      "role_arn"   = var.role_arn,

      "endpoints" = {
        "/debug" = {
          "get" = {
            security = ["asm"]
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

  # These rules apply against all endpoints
  firewall_configuration = {
    default_ruleset_block_mode = true

    # TODO: It's a list of strings, but why was it set to that?
    # blocked_ips = {
    #   script_gangsta = {
    #     ip_list  = ["10.0.0.1/32"],
    #     priority = 70
    #   }
    # }

    ip_rate_based_rule = {
      name     = "100_per_500_seconds",
      priority = 80,
      limit    = 100
    }

    ip_rate_url_based_rules = [
      {
        name          = "100_dings_per_500_seconds",
        priority      = 90,
        limit         = 100
        search_string = "/ding"
      }
    ]
  }
}

output "vpc_cidr" {
  value = module.api-app-x.vpc_cidr
}

output "vpc_tgw_id" {
  value = module.api-app-x.vpc_tgw_attachment_id
}

output "elasticache_cluster_address" {
  value = module.api-app-x.elasticache_cluster_address
}
