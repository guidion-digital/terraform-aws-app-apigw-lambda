module "method_settings" {
  source   = "./method_settings_loop"
  for_each = var.endpoints

  rest_api_id = var.rest_api_id
  stage_name  = var.stage_name
  endpoint    = each.key
  methods     = each.value
}
