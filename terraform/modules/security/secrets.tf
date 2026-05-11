resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#%&*+-=^_`|~"
  # Excludes @, /, \, " - characters PG connection strings dislike
}

resource "random_password" "moodle_admin" {
  length           = 24
  special          = true
  override_special = "!#%&*+-=^_`|~"
  # Same exclusions
}

# No CMK in Phase 1 per CLAUDE.md hard rule #3; uses aws/secretsmanager default. CMK introduced in Phase 2 for payment data isolation.
#checkov:skip=CKV_AWS_149: Same Phase 1 stance - no CMK for Secrets Manager (CLAUDE.md hard rule #3); revisit Phase 2.
#checkov:skip=CKV2_AWS_57: Automatic rotation deferred to Phase 2 per requirements §2.1; would require VPC-attached Lambda + Interface VPC Endpoint contradicting Phase 1 no-NAT cost stance.
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "db_master" {
  name        = "moodle/db/master"
  description = "RDS PostgreSQL master credentials for Moodle. Manual rotation in Phase 1; automatic rotation deferred to Phase 2 (requires VPC-attached Lambda + Interface VPC Endpoint, contradicts Phase 1 no-NAT cost stance per requirements §2.1)."
  # kms_key_id omitted - uses aws/secretsmanager AWS-managed key per CLAUDE.md hard rule #3 (no CMK in Phase 1)
  recovery_window_in_days = 7 # AWS default; allows undelete if accidentally destroyed

  tags = {
    Name = "moodle/db/master"
  }
}

# No CMK in Phase 1 per CLAUDE.md hard rule #3; uses aws/secretsmanager default. CMK introduced in Phase 2 for payment data isolation.
#checkov:skip=CKV_AWS_149: Same Phase 1 stance - no CMK for Secrets Manager (CLAUDE.md hard rule #3); revisit Phase 2.
#checkov:skip=CKV2_AWS_57: Automatic rotation deferred to Phase 2 per requirements §2.1; would require VPC-attached Lambda + Interface VPC Endpoint contradicting Phase 1 no-NAT cost stance.
#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "moodle_admin" {
  name        = "moodle/admin"
  description = "Initial Moodle administrator credentials. Used once during first-boot install (T-018 user-data); the operator rotates via Moodle UI on first login per docs/runbooks/first-deploy.md (T-033)."
  # kms_key_id omitted - uses aws/secretsmanager AWS-managed key per CLAUDE.md hard rule #3 (no CMK in Phase 1)
  recovery_window_in_days = 7

  tags = {
    Name = "moodle/admin"
  }
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    username = "moodle_admin"
    password = random_password.db_master.result
  })

  lifecycle {
    ignore_changes = [secret_string]
    # Prevents Terraform from overwriting the secret on every apply if
    # random_password regenerates. The initial seed is what matters;
    # subsequent rotation is manual per Phase 1 stance.
  }
}

resource "aws_secretsmanager_secret_version" "moodle_admin" {
  secret_id = aws_secretsmanager_secret.moodle_admin.id
  secret_string = jsonencode({
    username = "admin" # Moodle's default admin username
    password = random_password.moodle_admin.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
