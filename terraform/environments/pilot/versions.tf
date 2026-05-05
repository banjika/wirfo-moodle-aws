terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6, < 4.0"
    }
  }
}

locals {
  common_tags = {
    Project     = "moodle-academy"
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

# Used only by modules/dns_cdn to look up the ACM cert created in bootstrap.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}
