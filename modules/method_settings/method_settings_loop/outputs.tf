output "method_settings" {
  value = { for this_method, these_settings in aws_api_gateway_method_settings.these : this_method => these_settings.settings }
}
