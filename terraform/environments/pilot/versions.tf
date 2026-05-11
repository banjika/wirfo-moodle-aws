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

# Used by modules/dns_cdn (ACM cert lookup) and GuardDuty detector in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

# ---------------------------------------------------------------------------
# Regional provider aliases for GuardDuty account-wide coverage (T-025).
# Terraform requires statically declared provider blocks; one alias per
# opted-in region is unavoidable. default_tags must be repeated on each alias
# - Terraform does not inherit it from the default provider.
# ---------------------------------------------------------------------------

provider "aws" {
  alias  = "ap_northeast_1"
  region = "ap-northeast-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "ap_northeast_2"
  region = "ap-northeast-2"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "ap_northeast_3"
  region = "ap-northeast-3"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "ap_south_1"
  region = "ap-south-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "ap_southeast_2"
  region = "ap-southeast-2"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "ca_central_1"
  region = "ca-central-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "eu_north_1"
  region = "eu-north-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "eu_west_2"
  region = "eu-west-2"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "eu_west_3"
  region = "eu-west-3"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "sa_east_1"
  region = "sa-east-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "us_east_2"
  region = "us-east-2"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "us_west_1"
  region = "us-west-1"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"

  default_tags {
    tags = merge(local.common_tags, var.extra_tags)
  }
}
