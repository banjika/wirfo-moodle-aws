output "state_bucket_name" {
  description = "Name of the S3 bucket holding remote Terraform state."
  value       = aws_s3_bucket.tfstate.id
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking."
  value       = aws_dynamodb_table.tflock.name
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
