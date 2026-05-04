output "state_bucket_name" {
  description = "Name of the S3 bucket holding remote Terraform state."
  value       = aws_s3_bucket.tfstate.id
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking."
  value       = aws_dynamodb_table.tflock.name
}

output "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket receiving CloudTrail logs."
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail."
  value       = aws_cloudtrail.moodle_mgmt.arn
}

output "deploy_role_arn" {
  description = "ARN of the GitHub Actions OIDC deploy role."
  value       = aws_iam_role.deploy.arn
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 for CloudFront."
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}
