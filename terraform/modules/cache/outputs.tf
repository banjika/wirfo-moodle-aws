output "cache_endpoint" {
  description = "Primary endpoint hostname for the Valkey cluster. TLS-required; clients connect via redis://[auth]@<endpoint>:port."
  value       = aws_elasticache_replication_group.cache.primary_endpoint_address
}

output "cache_port" {
  description = "Cache port (6379)."
  value       = aws_elasticache_replication_group.cache.port
}

output "cache_cluster_id" {
  description = "Replication group identifier."
  value       = aws_elasticache_replication_group.cache.id
}

output "cache_auth_token" {
  description = "Valkey AUTH token. Sensitive — read by user-data at boot to populate Moodle's session/cache config. Not stored in Secrets Manager in Phase 1 (simplification); Phase 2 may migrate to Secrets Manager for consistency with the DB credentials."
  value       = random_password.valkey_auth.result
  sensitive   = true
}
