output "state_bucket_name" {
  description = "Name of the S3 bucket holding remote Terraform state. Filled by T-004."
  value       = null
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking. Filled by T-004."
  value       = null
}

output "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket receiving CloudTrail logs. Filled by T-005."
  value       = null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail. Filled by T-005."
  value       = null
}

output "deploy_role_arn" {
  description = "ARN of the GitHub Actions OIDC deploy role. Filled by T-007."
  value       = null
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 for CloudFront. Filled by T-006."
  value       = null
}
