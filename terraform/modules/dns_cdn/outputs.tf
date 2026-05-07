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
