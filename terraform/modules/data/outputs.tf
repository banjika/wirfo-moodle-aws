output "db_endpoint" {
  description = "Connection endpoint in host:port format."
  value       = aws_db_instance.rds.endpoint
}

output "db_port" {
  description = "PostgreSQL port (5432)."
  value       = aws_db_instance.rds.port
}

output "db_id" {
  description = "Identifier of the RDS instance."
  value       = aws_db_instance.rds.id
}

output "db_arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.rds.arn
}

output "db_resource_id" {
  description = "Internal RDS resource ID; used for Phase 3 IAM database authentication."
  value       = aws_db_instance.rds.resource_id
}
