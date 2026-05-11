terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.0, < 6.0"
      configuration_aliases = [aws.us_east_1]
      # Caller must pass aws.us_east_1 - used by the ACM cert data source.
      # CloudFront viewer certificates must live in us-east-1 (AWS hard requirement).
    }
  }
}
