output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.moodle.id
  description = "CloudFront distribution ID."
}

output "cloudfront_distribution_arn" {
  value       = aws_cloudfront_distribution.moodle.arn
  description = "CloudFront distribution ARN. Used by T-024 synthetics canary and T-023 alarms."
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.moodle.domain_name
  description = "CloudFront distribution's auto-assigned domain (d1234abcd.cloudfront.net). Used as the alias target on the A and AAAA Route 53 records."
}

output "ses_domain_identity_arn" {
  description = "SES domain identity ARN. Used by IAM policies that grant SES send permissions on the wirfoncloud.com identity (e.g., Phase 2 deploy role tightening)."
  value       = aws_ses_domain_identity.main.arn
}
