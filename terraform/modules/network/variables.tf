variable "project_name" {
  type        = string
  description = "Used for resource Name tags."
}

variable "environment" {
  type        = string
  description = "Used for resource Name tags."
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block for the VPC, e.g. \"10.0.0.0/16\"."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs to provision subnets in; index-aligned with public_subnet_cidrs and private_subnet_cidrs."

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "At least one availability zone must be specified."
  }
}

# Cross-variable validations below require Terraform >= 1.9 (cross-variable references
# in validation blocks were introduced in 1.9; the module floor is >= 1.7 but the
# effective minimum is >= 1.9 when these checks are active).
variable "public_subnet_cidrs" {
  type        = list(string)
  description = "One CIDR per AZ for public subnets; index-aligned with availability_zones."

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "public_subnet_cidrs must have the same number of entries as availability_zones."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "One CIDR per AZ for private subnets; index-aligned with availability_zones."

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "private_subnet_cidrs must have the same number of entries as availability_zones."
  }
}

# Used by T-010 flow logs.
variable "vpc_flow_log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days for VPC Flow Logs."
}
