variable "rest_api_id" {
  description = "Rest API ID to apply to"
}

variable "stage_name" {
  description = "Stage name in var.rest_api_id to apply to"
}

variable "endpoints" {
  description = "Settings to apply to the method"

  type = map(map(object({
    metrics_enabled        = bool
    logging_level          = string
    data_trace_enabled     = bool
    throttling_burst_limit = number
    throttling_rate_limit  = number
    caching_enabled        = bool
    cache_ttl_in_seconds   = number
    cache_data_encrypted   = bool
  })))
}
