output "instance_id" {
  description = "EC2 instance ID. Used by T-019 alarm and T-022 observability log group association."
  value       = aws_instance.moodle.id
}

output "instance_arn" {
  description = "EC2 instance ARN."
  value       = aws_instance.moodle.arn
}

output "eip_public_ip" {
  description = "Static public IPv4 address of the Moodle origin. Used by T-020 CloudFront origin configuration."
  value       = aws_eip.moodle.public_ip
}

output "eip_public_dns" {
  description = "Public DNS name of the EIP, e.g., ec2-X-X-X-X.eu-west-1.compute.amazonaws.com. Used as the CloudFront origin domain (preferable to raw IP for TLS SNI)."
  value       = aws_eip.moodle.public_dns
}
