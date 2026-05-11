resource "aws_db_subnet_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds"
  subnet_ids  = var.db_subnet_ids
  description = "Subnet group for Moodle RDS PostgreSQL - both private subnets supplied (RDS API requires >= 2 AZs); Phase 1 uses a single AZ via multi_az=false on the instance, RDS picks the active AZ at creation."

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-subnet-group"
  }
}

resource "aws_db_parameter_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-pg15"
  family      = "postgres15"
  description = "Custom Postgres 15 parameter group: enforce TLS, audit DDL statements, log slow queries."

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "log_statement"
    value        = "ddl"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "5000"
    apply_method = "immediate"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-pg15"
  }
}

# Phase 1 deferrals on RDS:
#   - Multi-AZ: CLAUDE.md hard rule #2 (single-AZ pilot)
#   - Performance Insights CMK: CLAUDE.md hard rule #3 (no CMK in P1)
#   - IAM database authentication: design.md §2.4 (db_resource_id reserved
#     for Phase 3; requires matching rds-db:connect IAM policy in
#     modules/compute not yet wired)
#   - Enhanced monitoring: Phase 2 deferral; requires a separate
#     monitoring.rds.amazonaws.com IAM role + monitoring_interval > 0.
#     Performance Insights (free 7-day retention) covers Phase 1
#     observability needs.
#checkov:skip=CKV_AWS_157: Phase 1 single-AZ per CLAUDE.md hard rule #2; var.rds_multi_az flips this in Phase 3.
#checkov:skip=CKV_AWS_118: Enhanced monitoring deferred to Phase 2; requires monitoring.rds.amazonaws.com IAM role. Performance Insights covers Phase 1 observability.
#checkov:skip=CKV_AWS_161: IAM DB auth deferred to Phase 3 per design.md §2.4; db_resource_id exported for the eventual modules/compute IAM policy.
#tfsec:ignore:aws-rds-enable-performance-insights-encryption
#tfsec:ignore:aws-rds-enable-iam-auth
resource "aws_db_instance" "rds" {
  identifier     = "${var.project_name}-${var.environment}-rds"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage_gb
  max_allocated_storage = var.db_max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = null
  # Explicit null - uses aws/rds default key per CLAUDE.md hard rule #3 (no CMK in Phase 1)

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  parameter_group_name   = aws_db_parameter_group.rds.name
  vpc_security_group_ids = [var.db_sg_id]

  multi_az = false
  # CLAUDE.md hard rule #2 - single-AZ. RDS picks the active AZ from the subnet group at creation.
  # availability_zone intentionally omitted - AZ pinning would conflict with Phase 3 Multi-AZ enable.

  publicly_accessible = false
  # NEVER public. RDS lives in private subnets behind the SG-to-SG rules from T-011.

  port     = 5432
  username = var.db_master_username
  password = var.db_master_password

  # Manual rotation in Phase 1; auto-rotation deferred to Phase 2 (would need VPC-attached Lambda +
  # Interface VPC Endpoint, contradicts Phase 1 no-NAT cost stance per requirements §2.1).

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-rds-final"
  # Static identifier - no timestamp() to avoid a forced plan diff on every run.
  copy_tags_to_snapshot = true

  backup_retention_period = var.db_backup_retention_days
  backup_window           = "01:00-02:00"
  # UTC; before maintenance window
  maintenance_window = "sun:02:30-sun:03:30"
  # UTC; aligns with requirements §4.3 planned maintenance window

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  # Free-tier days; longer retention costs ~$0.30/month per instance
  performance_insights_kms_key_id = null
  # Default aws/rds key per CLAUDE.md hard rule #3

  auto_minor_version_upgrade = true
  apply_immediately          = false
  # Schedule changes for the maintenance window, not immediate

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  # Stream Postgres + RDS upgrade logs to CW Logs (T-022 wires the matching log groups)

  tags = {
    Name = "${var.project_name}-${var.environment}-rds"
  }

  lifecycle {
    prevent_destroy = true
  }
}
