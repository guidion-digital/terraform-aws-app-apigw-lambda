variable "openapi_spec" {
  description = "Full OpenAPI spec. The module will not try to create one if this is supplied"
  type        = string
  default     = null
}

variable "validate_openapi_spec" {
  description = "If true, will attempt to valite the OpenAPI spec against the official schema using CherryBomb. CherryBomb must be installed"
  type        = bool
  default     = false
}

variable "stage" {
  description = "Used for naming certain resources. Not to be confused with var.api_stage"
}

variable "api_stage" {
  description = "The name to use for the API stage to deploy to. We only use one"
  default     = "live"
}

variable "overwrite_stage" {
  description = "Merge or overwrite the API? Overwriting has issues: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api#argument-reference"
  type        = bool
  default     = true
}

variable "project" {
  description = "Project (team) responsible for these resources"
}

variable "application_name" {
  description = "Name of the application these resources are tied to"
}

variable "metrics_enabled" {
  description = "Whether to enable CloudWatch metrics for these API"
  default     = true
}

variable "parent_zone" {
  description = "Zone in which subdomains will be created"
  type        = string
}

variable "main_subdomain" {
  description = "Main subdomain to give the certificate. Defaults to var.application_name"
  type        = string
  default     = null
}

variable "subdomains" {
  description = "Map of subdomains and their aliases that need to be created for the application (in var.parent_zone). Alias list can be empty"
  type        = list(string)

  default = []
}

variable "acm_certificate_arn" {
  description = "TODO: NOT IN USE YET — ARN of existing certificate to use. One is created if this is left blank"
  type        = string

  default = null
}

variable "parent_zone_in_domains" {
  description = "Whether to include the parent zone in the list of domains for the API Gateway. This variable has no effect if no subdomains are provided to use instead"
  type        = bool

  default = false
}

variable "DEPRECATED_acm_mode" {
  description = "Hack to keep backwards compatibility with instances that were deployed when the parent_zone was included as the main ACM domain"
  type        = bool
  default     = false
}

variable "clients" {
  description = "Map of consumers to create API keys for"

  type = map(object({
    throttle_settings = optional(object({
      path        = string
      burst_limit = optional(number)
      rate_limit  = optional(number)
    }), null)
  }))

  default = {}
}

variable "request_validators" {
  description = "https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-request-validators.html"
  type = map(object({
    validateRequestParameters = optional(bool, false),
    validateRequestBody       = optional(bool, false)
  }))

  default = {
    "all" = {
      validateRequestParameters = true,
      validateRequestBody       = true
    },
    "params-only" = {
      validateRequestParameters = true,
      validateRequestBody       = false
    }
    "body-only" = {
      validateRequestParameters = false,
      validateRequestBody       = true
    },
    "none" = {
      validateRequestParameters = false,
      validateRequestBody       = false
    }
  }
}

# Create an authorizer: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_authorizer
variable "authorizers" {
  type = object({
    create_custom = optional(map(object({
      name        = optional(string, "Authorization"),
      secret_name = optional(string, "common/api-bearer-tokens")
    })), {}),

    custom = optional(map(object({
      name                   = optional(string, "Authorization"),
      type                   = optional(string, "apiKey"),
      in                     = optional(string, "header"),
      authorizer_ttl         = optional(number, 300),
      authorizer_credentials = optional(string, null),
      authorizer_uri         = string,
      }
    )), {}),

    cognito = optional(map(object({
      name          = optional(string, "Authorization"),
      type          = optional(string, "apiKey"),
      in            = optional(string, "header"),
      provider_arns = list(string)
      }
    )), {})
  })

  default = {}
}

variable "common_endpoint_configuration" {
  description = "Values to apply to all endpoints in var.lambdas{}.endpoints"

  type = object({
    request_validator = optional(string)
  })

  default = {
    request_validator = null
  }
}

variable "common_lambda_configuration" {
  description = "Values to apply to all Lambdas in var.lambdas"

  type = object({
    runtime                        = optional(string),
    handler                        = optional(string),
    reserved_concurrent_executions = optional(number),
    memory_size                    = optional(number, null),
    timeout                        = optional(number, null),
    environment                    = optional(map(string)),
    publish_version                = optional(bool),
    latest_version_alias           = optional(string),
  })
}

variable "domain_account_role" {
  description = "If the Route53 record is held in another account, pass a role to assume in that account here"
  default     = null
}

variable "lambdas" {
  description = "Description of the Lambdas to deploy"

  type = map(object({
    publish_version                = optional(bool),
    latest_version_alias           = optional(string),
    vpc_enabled                    = optional(bool, false),
    runtime                        = optional(string),
    source_dir                     = string,
    handler                        = optional(string),
    role_arn                       = optional(string),
    reserved_concurrent_executions = optional(number),
    memory_size                    = optional(number, null),
    timeout                        = optional(number, null),
    environment                    = optional(map(string)),

    vpc_config = optional(object({
      subnet_ids         = optional(list(string)),
      security_group_ids = optional(list(string))
    }), {})

    security_group_rules = optional(object({
      egress = optional(map(object({
        protocol  = string,
        cidr      = string,
        from_port = number,
        to_port   = number
        })
      )),
      ingress = optional(map(object({
        protocol  = string,
        cidr      = string,
        from_port = number,
        to_port   = number
        })
      ), {}),
      }
    ), {}),

    event_triggers = optional(object({
      sqs_queues = optional(list(string), []),

      dynamodb_tables = optional(map(object({
        batch_size                     = optional(number, 1),
        starting_position              = optional(string, "LATEST")
        maximum_retry_attempts         = optional(number, -1)
        bisect_batch_on_function_error = optional(bool, false)
        })),
      {}),

      cloudwatch = optional(
        object(
          {
            schedule = optional(string, null)
            pattern  = optional(string, null)
          }
          ), {
          schedule = null,
          pattern  = null
        }
      )
    }), {}),

    allow_apigw_invocation = optional(bool, false)

    endpoints = optional(map(map(object({
      security               = optional(list(string), []),
      metrics_enabled        = optional(bool, false),
      logging_level          = optional(string, "ERROR"),
      data_trace_enabled     = optional(bool, false),
      throttling_burst_limit = optional(number, -1),
      throttling_rate_limit  = optional(number, -1),
      caching_enabled        = optional(bool, false),
      cache_ttl_in_seconds   = optional(number),
      cache_data_encrypted   = optional(bool, false),
      http_method            = optional(string)
      responses = optional(map(object({
        description = string,
        headers = optional(map(object({
          value = optional(string),
          schema = optional(object({
            type = optional(string, "string")
            }), {
            schema = {
              type = "string"
            }
          })
          # Not implemented
          # content = optional(map(object({
          #   schema   = optional(any),
          #   example  = optional(any),
          #   examples = optional(any),
          #   encoding = optional(map(string))
          # }))),
          # links = optional(map(string), {})
        })))
        })),
        {
          "200" = {
            "description" = "200 response",
          }
      }),
      # This is a cheat for when we don't want to be so verbose as to take the
      # header value from the above responses.headers object
      AccessControlAllowMethods = optional(string),
      request_validator         = optional(string),
      integration = optional(object({
        type = optional(string, "aws_proxy"),
        responses = optional(map(
          object({
            statusCode         = string,
            responseParameters = map(string)
          })),
        {}),
        request_templates = optional(map(string)),
        content_handling  = optional(string)
        }
      ), {}),
      parameters = optional(map(object({
        in       = optional(string, "query"),
        required = optional(bool, true),
        schema   = optional(map(string), { "type" = "string" })
      })), {})
    }))), {})
  }))
}

variable "global_method_configuration" {
  description = "WIP: Only `logging_level` is currently used. Configuration to apply to all methods. Can be overriden on the var.lambdas{} level"
  default     = {}

  type = object({
    security = optional(list(string), []),
    metrics_enabled : optional(bool, false),
    logging_level : optional(string, "ERROR"),
    data_trace_enabled : optional(bool, false),
    throttling_burst_limit : optional(number, -1),
    throttling_rate_limit : optional(number, -1),
    caching_enabled : optional(bool, false),
    cache_ttl_in_seconds : optional(number, -1),
    cache_data_encrypted : optional(bool, false)
  })
}

# TODO: https://guidiondev.atlassian.net/browse/CI-175
variable "api_keys_share" {
  description = "Map of {type to [IAM ARNs]} of the role to share the API keys with. Must be given if setting var.clients"
  type        = map(list(string))
  default     = {}
}

variable "vpc_config" {
  description = "VPC will be created for this application if supplied"

  type = object({
    vpc_cidr = string,
    az_count = optional(number, 3)
  })

  default = null
}

variable "endpoint_types" {
  description = "TODO: Only EDGE is fully supported right now, but REGIONAL will probably already work too"
  type        = list(any)
  default     = ["EDGE"]

  validation {
    condition     = length(setintersection(var.endpoint_types, ["EDGE", "PRIVATE", "REGIONAL"])) != 0
    error_message = "List must consist of only 'EDGE', 'REGIONAL', or 'PRIVATE'"
  }
}

variable "firewall_configuration" {
  description = "Enables WAF if any values are supplied"

  type = object({
    default_ruleset_count_mode = optional(bool, false),
    default_ruleset_block_mode = optional(bool, false),

    ip_rate_based_rule = optional(
      object({
        name          = string,
        priority      = number,
        limit         = number,
        action        = optional(string, "count"),
        response_code = optional(number, 403)
      }),

      null
    ),

    ip_rate_url_based_rules = optional(
      list(object({
        name          = string,
        priority      = number,
        limit         = number,
        action        = optional(string, "count"),
        response_code = optional(number, 403),
        search_string = string,
        # EXACTLY, STARTS_WITH, ENDS_WITH, CONTAINS, or CONTAINS_WORD
        positional_constraint = optional(string, "EXACTLY")
      })),
    [])

    whitelist   = optional(list(string), []),
    blocked_ips = optional(list(string), [])

    filtered_header_rule = optional(object({
      header_types  = list(string),
      priority      = number,
      header_value  = string,
      action        = optional(string, "count"),
      search_string = optional(string, "")
      }),

      { "action" : "block",
        "header_types" : [],
        "header_value" : "",
        "priority" : 100,
        "search_string" : ""
      }
    )

    managed_rules = optional(
      list(object({
        name            = string,
        priority        = optional(number, null),
        override_action = optional(string, "count"),
        excluded_rules  = optional(list(string), null),
        vendor_name     = string
      })),

      [
        {
          "excluded_rules" : [],
          "name" : "AWSManagedRulesCommonRuleSet",
          "override_action" : "count",
          "priority" : 10,
          "vendor_name" : "AWS"
        },
        {
          "excluded_rules" : [],
          "name" : "AWSManagedRulesAmazonIpReputationList",
          "override_action" : "count",
          "priority" : 20,
          "vendor_name" : "AWS"
        },
        {
          "excluded_rules" : [],
          "name" : "AWSManagedRulesKnownBadInputsRuleSet",
          "override_action" : "count",
          "priority" : 30,
          "vendor_name" : "AWS"
        },
        {
          "excluded_rules" : [],
          "name" : "AWSManagedRulesSQLiRuleSet",
          "override_action" : "count",
          "priority" : 40, "vendor_name" : "AWS"
        },
        {
          "excluded_rules" : [],
          "name" : "AWSManagedRulesLinuxRuleSet",
          "override_action" : "count",
          "priority" : 50,
          "vendor_name" : "AWS"
        },
        {
          "excluded_rules" : [],
          "name" : "AWSManagedRulesUnixRuleSet",
          "override_action" : "count",
          "priority" : 60, "vendor_name" : "AWS"
        }
    ])
  })

  default = null
}

locals {
  name              = var.application_name
  put_rest_api_mode = var.overwrite_stage == true ? "overwrite" : "merge"

  waf_rules = var.firewall_configuration == null ? [""] : concat([
    "whitelist",
    "blocked_ips",
    "AWSManagedRulesCommonRuleSet",
    "AWSManagedRulesAmazonIpReputationList",
    "AWSManagedRulesKnownBadInputsRuleSet",
    "AWSManagedRulesSQLiRuleSet",
    "AWSManagedRulesLinuxRuleSet",
    "AWSManagedRulesUnixRuleSet",
    var.firewall_configuration.ip_rate_based_rule != null ? var.firewall_configuration.ip_rate_based_rule.name : ""
    ],
    var.firewall_configuration.ip_rate_url_based_rules[*].name,
    var.firewall_configuration.filtered_header_rule.header_types
  )

  managed_rules = var.firewall_configuration == null ? null : var.firewall_configuration.default_ruleset_block_mode == true ? [
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesCommonRuleSet",
      "override_action" : "none",
      "priority" : 10,
      "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesAmazonIpReputationList",
      "override_action" : "none",
      "priority" : 20,
      "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesKnownBadInputsRuleSet",
      "override_action" : "none",
      "priority" : 30,
      "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesSQLiRuleSet",
      "override_action" : "none",
      "priority" : 40, "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesLinuxRuleSet",
      "override_action" : "none",
      "priority" : 50,
      "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesUnixRuleSet",
      "override_action" : "none",
      "priority" : 60, "vendor_name" : "AWS"
    }
    ] : [
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesCommonRuleSet",
      "override_action" : "count",
      "priority" : 10,
      "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesAmazonIpReputationList",
      "override_action" : "count",
      "priority" : 20,
      "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesKnownBadInputsRuleSet",
      "override_action" : "count",
      "priority" : 30,
      "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesSQLiRuleSet",
      "override_action" : "count",
      "priority" : 40, "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesLinuxRuleSet",
      "override_action" : "count",
      "priority" : 50,
      "vendor_name" : "AWS"
    },
    {
      "excluded_rules" : [],
      "name" : "AWSManagedRulesUnixRuleSet",
      "override_action" : "count",
      "priority" : 60, "vendor_name" : "AWS"
    }
  ]
}

# For supporting resources module

variable "sqs_queues" {
  description = "SQS queues will be created if values are supplied for this"

  type = map(object({
    content_based_deduplication     = optional(bool, null),
    deduplication_scope             = optional(string, null),
    delay_seconds                   = optional(number, null),
    dlq_content_based_deduplication = optional(bool, null),
    dlq_deduplication_scope         = optional(string, null),
    dlq_delay_seconds               = optional(number, null),
    dlq_message_retention_seconds   = optional(number, null),
    dlq_receive_wait_time_seconds   = optional(number, null),
    dlq_visibility_timeout_seconds  = optional(number, null),
    fifo_queue                      = optional(bool, false),
    fifo_throughput_limit           = optional(string, null),
    max_message_size                = optional(number, null),
    message_retention_seconds       = optional(number, null),
    receive_wait_time_seconds       = optional(number, null),
    visibility_timeout_seconds      = optional(number, null),
    readwrite_arns                  = optional(list(string), [])
    read_arns                       = optional(list(string), []),
    redrive_policy = optional(object({
      maxReceiveCount = optional(number, 10)
      }), {
      maxReceiveCount = 10
    })
  }))

  default = {}
}

variable "namespace_supporting_resources" {
  description = "Whether to prepend var.application_name to supporting resources like var.dynamodb_tables"
  type        = bool
  default     = true
}

variable "dynamodb_tables" {
  description = "DynamoDB tables will be created if values are supplied for this"

  # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-dynamodb-table.html
  type = map(object({
    attributes = list(map(string)),
    hash_key   = string,
    range_key  = optional(string),

    billing_mode                          = optional(string, "PROVISIONED"),
    read_capacity                         = optional(number, 5),
    write_capacity                        = optional(number, 5),
    autoscaling_enabled                   = optional(bool, true),
    ignore_changes_global_secondary_index = optional(bool, false),
    ttl_attribute_name                    = optional(string, ""),
    stream_view_type                      = optional(string, "NEW_IMAGE"),
    point_in_time_recovery_enabled        = optional(bool, false),
    timeouts                              = optional(map(string), { "create" : "10m", "delete" : "10m", "update" : "60m" }),

    autoscaling_read_scale_in_cooldown  = optional(number, 50),
    autoscaling_read_scale_out_cooldown = optional(number, 40),
    autoscaling_read_target_value       = optional(number, 45),
    autoscaling_read_max_capacity       = optional(number, 10),

    autoscaling_write_scale_in_cooldown  = optional(number, 50),
    autoscaling_write_scale_out_cooldown = optional(number, 40),
    autoscaling_write_target_value       = optional(number, 45),
    autoscaling_write_max_capacity       = optional(number, 10),

    global_secondary_indexes : optional(list(
      object({
        name               = string,
        hash_key           = string,
        range_key          = string,
        projection_type    = optional(string, "INCLUDE"),
        non_key_attributes = list(string),
        write_capacity     = optional(number, 10)
        read_capacity      = optional(number, 10)

        autoscaling = optional(object({
          read_max_capacity  = optional(number, 30),
          read_min_capacity  = optional(number, 10),
          write_max_capacity = optional(number, 30),
          write_min_capacity = optional(number, 10)
        }), null)
      })),
    [])
  }))

  default = {}
}

variable "grafana_promtail_lambda_arn" {
  description = "ARN of Lambda that will forward on logs to Grafana"
  default     = null
}

variable "secrets" {
  description = "Object of secrets, mapped to their settings"

  type = map(object({
    description                    = optional(string, null)
    kms_key_id                     = optional(string, null)
    recovery_window_in_days        = optional(number, 7)
    force_overwrite_replica_secret = optional(bool, false)

    allowed_update = optional(map(list(string)), null)

    rotation_configuration = optional(object({
      lambda_arn          = string
      schedule_expression = string
    }), null)
  }))

  default = {}
}

variable "elasticache" {
  description = "Map of Elasticache clusters to create"

  type = map(object({
    name                       = optional(string, null)
    project                    = string
    application_name           = string
    stage                      = string
    engine                     = optional(string, "memcached")
    engine_version             = optional(string, "1.6.17")
    node_type                  = optional(string, "cache.t4g.micro")
    apply_immediately          = optional(bool, false)
    transit_encryption_enabled = optional(bool, true)
    auto_minor_version_upgrade = optional(bool, null)
    maintenance_window         = optional(string, "sun:05:00-sun:09:00")
    parameters = optional(list(object({
      name  = string
      value = string
    })), [])
    ip_discovery                 = optional(string, "ipv4")
    network_type                 = optional(string, "ipv4")
    port                         = optional(number, null)
    notification_topic_arn       = optional(string, null)
    az_mode                      = optional(string, "single-az")
    availability_zone            = optional(string, null)
    preferred_availability_zones = optional(list(string), null)
    num_cache_nodes              = optional(number, 1)
    vpc_id                       = optional(string, null)
    subnet_ids                   = optional(list(string), null)
    security_group_rules = optional(map(object({
      type        = string
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = list(string)
    })), {})
    security_group_ids      = optional(list(string), [])
    allowed_cidrs           = optional(list(string), null)
    allowed_security_groups = optional(list(string), [])
  }))

  default = {}
}

variable "ssm_parameters" {
  description = "Map of SSM parameters, and their configuration"

  type = map(object({
    description    = optional(string, "")
    type           = optional(string, null)
    value          = optional(string, null)
    insecure_value = optional(string, null)
    ignore_changes = optional(bool, false)
    key_id         = optional(string, null)
    tier           = optional(string, "standard")
    tags           = optional(map(string), {})
  }))

  default = {}
}
