terraform {
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
