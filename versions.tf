terraform {
  # Preconditions (see aws_api_gateway_rest_api.this) need >= 1.2
  required_version = ">= 1.2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.7.0, < 7.0.0"
      configuration_aliases = [
        aws.requester_external,
        aws.dns_account_external
      ]
    }
  }
}
