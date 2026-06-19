provider "aws" {
  alias  = "dns_account"
  region = "us-east-1"

  dynamic "assume_role" {
    for_each = local.domain_account_role

    content {
      role_arn = assume_role.value
    }
  }
}

provider "aws" {
  alias  = "requester"
  region = "us-east-1"
}

module "acm_validations" {
  count = var.acm_certificate_arn == null ? 1 : 0

  source  = "guidion-digital/helper-acm-validation/aws"
  version = "~> 2.0"

  providers = {
    aws.dns_account = aws.dns_account_external
    aws.requester   = aws.requester_external
  }

  parent_zone            = var.parent_zone
  main_subdomain         = var.main_subdomain == null ? var.application_name : var.main_subdomain
  subdomains             = var.subdomains
  parent_zone_in_domains = var.DEPRECATED_acm_mode ? true : var.parent_zone_in_domains
  tags                   = local.tags
}

locals {
  domain_account_role = var.domain_account_role == null ? [] : toset([var.domain_account_role])
}

# We separate out "parent(_zone)" and the normal subdomains because if we ever
# needed to create a DNS record for the parent zone, it would have to be a
# special A alias type, and this way we can use a conditional for picking up
# the right aws_api_gateway_domain_name resource for that
#
# i.e. This (single) resource will be created if var.parent_zone_in_domains is
# true, and there will cause the aws_route53_record and aws_api_gateway_base_path_mapping
# resources for "parents" (parent_zone) to also be created, (which is special A alias)
resource "aws_api_gateway_domain_name" "parents" {
  for_each = var.parent_zone_in_domains ? { (one(module.acm_validations).main_domain) = "true" } : {}

  certificate_arn = one(module.acm_validations).certificate_arn
  domain_name     = each.key
  tags            = local.tags

  endpoint_configuration {
    types = var.endpoint_types
  }

  lifecycle {
    create_before_destroy = true
  }
}
# Resource(s) below will be created for all subdomains that have been given,
# causing the aws_route53_record and aws_api_gateway_base_path_mapping resources
# for alt_domains (subdomain) resources to be created
resource "aws_api_gateway_domain_name" "alt_domains" {
  for_each = toset(one(module.acm_validations).all_subdomains)

  certificate_arn = one(module.acm_validations).certificate_arn
  domain_name     = each.key
  tags            = local.tags

  endpoint_configuration {
    types = var.endpoint_types
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_base_path_mapping" "parents" {
  for_each   = aws_api_gateway_domain_name.parents
  depends_on = [aws_api_gateway_stage.this, module.acm_validations]

  api_id      = aws_api_gateway_rest_api.this.id
  domain_name = each.value.domain_name
  stage_name  = var.api_stage

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_base_path_mapping" "alt_domains" {
  for_each   = aws_api_gateway_domain_name.alt_domains
  depends_on = [aws_api_gateway_stage.this, module.acm_validations]

  api_id      = aws_api_gateway_rest_api.this.id
  domain_name = each.value.domain_name
  stage_name  = var.api_stage

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "this" {
  provider = aws.dns_account

  name         = var.parent_zone
  private_zone = false
}

resource "aws_route53_record" "parents" {
  for_each = aws_api_gateway_domain_name.parents

  provider = aws.dns_account
  zone_id  = data.aws_route53_zone.this.id
  name     = each.key
  type     = "A"

  alias {
    zone_id                = each.value.cloudfront_zone_id
    name                   = each.value.cloudfront_domain_name
    evaluate_target_health = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "alt_domains" {
  for_each = aws_api_gateway_domain_name.alt_domains

  provider = aws.dns_account
  zone_id  = data.aws_route53_zone.this.id
  name     = each.key
  type     = "CNAME"
  ttl      = 60
  records  = [each.value.cloudfront_domain_name]

  lifecycle {
    create_before_destroy = true
  }
}
