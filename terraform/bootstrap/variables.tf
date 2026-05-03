# ---------------------------------------------------------------------------
# Bootstrap identity & backend
# ---------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "Bootstrap default region for the state bucket, lock table, and CloudTrail."
}

# tflint-ignore: terraform_unused_declarations
variable "state_bucket_name" {
  type        = string
  description = "S3 bucket name for workload Terraform state. Recommended: wirfo-moodle-tfstate-<account-id>."
}

# tflint-ignore: terraform_unused_declarations
variable "lock_table_name" {
  type        = string
  default     = "wirfo-moodle-tflock"
  description = "DynamoDB table name for workload state locking."
}

# tflint-ignore: terraform_unused_declarations
variable "cloudtrail_bucket_name" {
  type        = string
  description = "S3 bucket name for CloudTrail logs. Recommended: wirfo-moodle-cloudtrail-<account-id>."
}

# ---------------------------------------------------------------------------
# DNS & certificate
# ---------------------------------------------------------------------------

# tflint-ignore: terraform_unused_declarations
variable "domain_name" {
  type        = string
  default     = "academy.wirfoncloud.com"
  description = "Subject of the ACM certificate created for CloudFront in us-east-1."
}

# tflint-ignore: terraform_unused_declarations
variable "acm_subject_alternative_names" {
  type        = list(string)
  default     = []
  description = "SANs to add to the CloudFront ACM certificate. None required in Phase 1."
}

# ---------------------------------------------------------------------------
# GitHub OIDC
# ---------------------------------------------------------------------------

# tflint-ignore: terraform_unused_declarations
variable "github_repo" {
  type        = string
  default     = "banjika/wirfo-moodle-aws"
  description = "<owner>/<repo> used to scope the OIDC trust for the GitHub Actions deploy role."

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in <owner>/<repo> format."
  }
}
