output "openapi_spec" {
  description = "Full OpenAPI spec generated from all the Lambdas, methods, etc."
  value       = local.openapi_spec
}

output "openapi_spec_mocked" {
  description = "Full OpenAPI spec generated from all the Lambdas, methods, etc. — slightly mocked for the validator test"
  value       = local.full_openapi_spec_mocked
}

output "lambdas_local" {
  description = "Local lambdas object generated from var.lambdas and var.common_lambda_configuration and some other things"
  value       = local.lambdas
}

output "lambdas" {
  description = "All output from creating Lambdas"
  value       = module.api_lambdas
}

output "subdomains" {
  description = "DNS records that were created for the custom domain name"
  value       = var.subdomains
}

output "lambda_arns" {
  value = { for this_lambda, these_values in module.api_lambdas : this_lambda => these_values.lambda_arn }
}

output "vpc_id" {
  value = var.vpc_config != null ? module.vpc[0].vpc_attributes.id : "none"
}

output "vpc_cidr" {
  value = var.vpc_config != null ? module.vpc[0].vpc_attributes.cidr_block : "none"
}

output "vpc_tgw_id" {
  value = var.vpc_config != null ? module.vpc[0].transit_gateway_attachment_id : "none"
}

output "vpc_tgw_attachment_id" {
  value = var.vpc_config != null ? module.vpc[0].transit_gateway_attachment_id : "none"
}

output "method_settings" {
  description = "Ultimately resultant settings applied to endpoint methods"
  value       = module.method_settings
}

output "dyanmodb_table_stream_arns" {
  description = "ARNs of any DynamoDB tables that get created"
  value       = module.supporting_resources.dyanmodb_table_stream_arns
}

output "api_id" {
  description = "ID of the Rest API"
  value       = aws_api_gateway_rest_api.this.id
}

output "secrets" {
  description = "An object map of all the secrets generated, along with their attributes"
  value = { for this_secret, these_values in module.secrets :
    this_secret => these_values.secrets
  }
}

output "secret_ids" {
  description = "IDs of all the secrets created"

  value = {
    for this_secret, these_attributes in module.secrets :
    this_secret => these_attributes.ids
  }
}

output "secret_arns" {
  description = "ARNs of all the secrets created"

  value = {
    for this_secret, these_attributes in module.secrets :
    this_secret => these_attributes.arns
  }
}

output "elasticache_arn" {
  value = try(module.elasticache[0].arn, null)
}

output "elasticache_cache_nodes" {
  value = try(module.elasticache[0].cache_nodes, null)
}

output "elasticache_cluster_address" {
  value = try(module.elasticache[0].cluster_address, null)
}

output "elasticache_configuration_endpoint" {
  value = try(module.elasticache[0].configuration_endpoint, null)
}

output "elasticache_engine_version_actual" {
  value = try(module.elasticache[0].engine_version_actual, null)
}
