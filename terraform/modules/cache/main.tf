resource "random_password" "valkey_auth" {
  length  = 64
  special = true
  # Valkey AUTH token allowed special characters per AWS docs.
  # Excludes @, /, \, ", :, ' (would break Moodle's connection string parsing).
  override_special = "!&#$^<>-"
}

resource "aws_elasticache_subnet_group" "cache" {
  name       = "${var.project_name}-${var.environment}-cache"
  subnet_ids = var.cache_subnet_ids
  # Both private subnets supplied (AWS API requires multi-AZ-capable subnet group);
  # the replication group itself is single-node single-AZ via multi_az_enabled = false.
  description = "Subnet group for Moodle Valkey cache. Both private subnets supplied (AWS API requires multi-AZ-capable subnet group); the replication group itself is single-node single-AZ via multi_az_enabled = false."

  tags = {
    Name = "${var.project_name}-${var.environment}-cache-subnet-group"
  }
}

resource "aws_elasticache_parameter_group" "cache" {
  # CRITICAL: family format is "valkey7" (no dot, no patch).
  # engine_version on the replication group is "7.2" (exact version with dot).
  # These DIFFERENT formats are the AWS API contract. Setting family = "valkey7.2"
  # causes InvalidParameterCombinationException at apply time.
  family      = "valkey7"
  name        = "${var.project_name}-${var.environment}-cache-valkey7"
  description = "Custom Valkey 7 parameter group for Moodle cache. Default settings; reserved for future tuning."

  tags = {
    Name = "${var.project_name}-${var.environment}-cache-valkey7"
  }
}

# Phase 1 deferrals on ElastiCache:
#   - Multi-AZ / replicas: CLAUDE.md hard rule #2 (single-AZ pilot). Phase 3 enables HA
#     via num_node_groups > 1 / replicas_per_node_group > 0 / multi_az_enabled = true.
#   - Snapshots: ephemeral session/MUC storage only; no durable data warrants backup.
#     DB (RDS) and file storage (EFS) hold data of record.
#   - CMK at rest: CLAUDE.md hard rule #3 (no CMK in Phase 1); uses aws/elasticache default.
#checkov:skip=CKV_AWS_191: Phase 1 no CMK per CLAUDE.md hard rule #3; uses aws/elasticache default key. CMK deferred to Phase 2.
#checkov:skip=CKV2_AWS_50: Phase 1 single-AZ per CLAUDE.md hard rule #2; automatic_failover_enabled=false required when replicas_per_node_group=0. Phase 3 enables HA via cache_cluster_mode toggle.
resource "aws_elasticache_replication_group" "cache" {
  replication_group_id = "${var.project_name}-${var.environment}-cache"
  # ElastiCache replication group IDs are case-sensitive in AWS but the API normalises them
  # to lowercase. Use lowercase project_name and environment to avoid drift.
  description = "Moodle session + Universal Cache storage. Single-node single-AZ Phase 1; Phase 3 enables HA via var.cache_cluster_mode toggle."

  engine         = "valkey"
  engine_version = var.cache_engine_version
  # "7.2" — exact version with dot. The parameter group family ("valkey7") uses a different format.
  node_type = var.cache_node_type

  num_node_groups = 1
  # One primary shard
  replicas_per_node_group = 0
  # No replicas (single-node)
  automatic_failover_enabled = false
  # Cannot be true with replicas_per_node_group = 0
  multi_az_enabled = false
  # CLAUDE.md hard rule #2 — single-AZ stance. ElastiCache picks the AZ at creation from the subnet group.
  # availability_zone intentionally omitted — pinning would conflict with Phase 3 HA enable.

  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.cache.name
  subnet_group_name    = aws_elasticache_subnet_group.cache.name
  security_group_ids   = [var.cache_sg_id]

  at_rest_encryption_enabled = true
  # CLAUDE.md hard rule #9
  kms_key_id = null
  # Explicit null — uses aws/elasticache default key per CLAUDE.md hard rule #3 (no CMK in Phase 1).

  transit_encryption_enabled = true
  # CLAUDE.md hard rule #10 — TLS in transit
  transit_encryption_mode = "required"
  # Reject non-TLS connections. Stricter than default "preferred" (which accepts plaintext during transition).

  auth_token = random_password.valkey_auth.result
  # AUTH token requires transit_encryption_enabled = true (AWS enforces). Defence in depth: TLS + auth.
  auth_token_update_strategy = "ROTATE"
  # When auth token changes (manual rotation Phase 1), ROTATE allows the cluster to accept both old and new
  # during transition rather than DELETE which forces immediate cutover.

  apply_immediately = false
  # Schedule changes for the maintenance window
  maintenance_window = "sun:03:30-sun:04:30"
  # UTC; sequenced after RDS maintenance window (sun:02:30-sun:03:30) so cache and DB don't restart simultaneously.

  snapshot_retention_limit = 0
  # No snapshots in Phase 1 — Valkey is session/cache only, no durable data.
  # DB (RDS) and EFS hold data of record.

  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-${var.environment}-cache"
  }

  lifecycle {
    prevent_destroy = false
    # Cache is ephemeral — losing it forces session re-login but not data loss.
    # Unlike RDS/EFS, no prevent_destroy needed.
    ignore_changes = [
      num_cache_clusters,
      # Computed value AWS may adjust; ignore to prevent plan churn.
    ]
  }
}
