output "web_sg_id" {
  description = "ID of the web-tier security group (EC2 instance)."
  value       = aws_security_group.web.id
}

output "db_sg_id" {
  description = "ID of the database-tier security group (RDS)."
  value       = aws_security_group.db.id
}

output "cache_sg_id" {
  description = "ID of the cache-tier security group (ElastiCache Valkey)."
  value       = aws_security_group.cache.id
}

output "efs_sg_id" {
  description = "ID of the EFS mount-target security group."
  value       = aws_security_group.efs.id
}

output "ec2_instance_profile_name" {
  description = "Name of the IAM instance profile for the Moodle EC2 instance."
  value       = aws_iam_instance_profile.moodle_ec2.name
}

output "backup_role_arn" {
  description = "ARN of the IAM role assumed by AWS Backup."
  value       = aws_iam_role.aws_backup.arn
}
