output "efs_id" {
  value       = aws_efs_file_system.moodledata.id
  description = "EFS file system ID. Used by EC2 user-data to mount /var/moodledata."
}

output "efs_arn" {
  value       = aws_efs_file_system.moodledata.arn
  description = "EFS file system ARN. Used by AWS Backup selection in T-017."
}

output "efs_dns_name" {
  value       = aws_efs_file_system.moodledata.dns_name
  description = "EFS DNS name. Used by EC2 user-data for the mount command (TLS-required)."
}
