resource "aws_api_gateway_method_settings" "these" {
  for_each = var.methods

  rest_api_id = var.rest_api_id
  stage_name  = var.stage_name
  method_path = "${trimprefix(var.endpoint, "/")}/${upper(each.key)}"

  settings {
    metrics_enabled        = each.value["metrics_enabled"]
    logging_level          = each.value["logging_level"]
    data_trace_enabled     = each.value["data_trace_enabled"]
    throttling_burst_limit = each.value["throttling_burst_limit"]
    throttling_rate_limit  = each.value["throttling_rate_limit"]
    caching_enabled        = each.value["caching_enabled"]
    cache_ttl_in_seconds   = each.value["cache_ttl_in_seconds"]
    cache_data_encrypted   = each.value["cache_data_encrypted"]
  }
}
