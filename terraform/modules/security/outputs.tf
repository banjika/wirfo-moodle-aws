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
