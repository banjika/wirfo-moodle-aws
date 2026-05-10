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

output "ec2_role_arn" {
  description = "ARN of the IAM role assumed by the Moodle EC2 instance. Consumed by modules/storage (EFS file system policy explicit-allow) and modules/data (future IAM DB auth)."
  value       = aws_iam_role.moodle_ec2.arn
}

output "backup_role_arn" {
  description = "ARN of the IAM role assumed by AWS Backup."
  value       = aws_iam_role.aws_backup.arn
}

output "db_secret_arn" {
  description = "ARN of the RDS master credentials secret. Consumed by modules/data (T-014) to set the RDS master password."
  value       = aws_secretsmanager_secret.db_master.arn
}

output "admin_secret_arn" {
  description = "ARN of the initial Moodle admin credentials secret. Consumed by modules/compute (T-018) at first boot."
  value       = aws_secretsmanager_secret.moodle_admin.arn
}

output "db_master_password" {
  description = "RDS master password (sensitive). Used by modules/data (T-014) to set RDS master credentials. Stored in Terraform state — never log to console."
  value       = random_password.db_master.result
  sensitive   = true
}
