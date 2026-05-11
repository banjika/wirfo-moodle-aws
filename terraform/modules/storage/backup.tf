# Phase 1 deferrals on AWS Backup vault:
#   - CMK encryption: CLAUDE.md hard rule #3 (no CMK in Phase 1); uses aws/backup default.
#     CMK introduced in Phase 2 alongside payment data isolation.
#checkov:skip=CKV_AWS_166: Phase 1 no CMK per CLAUDE.md hard rule #3 and design.md §10 row 3 (no vault-level CMK in Phase 1); uses aws/backup default key. CMK introduced in Phase 2 alongside payment data isolation.
resource "aws_backup_vault" "moodle" {
  name        = "${var.project_name}-${var.environment}-moodle-backup-vault"
  kms_key_arn = null
  # Explicit null - uses aws/backup AWS-managed key per CLAUDE.md
  # hard rule #3 and design.md §10 row 3 (no vault-level CMK in
  # Phase 1). CMK introduced in Phase 2 alongside payment data isolation.

  tags = {
    Name = "${var.project_name}-${var.environment}-moodle-backup-vault"
  }
}

resource "aws_backup_plan" "moodle" {
  name = "${var.project_name}-${var.environment}-moodle-backup-plan"

  rule {
    rule_name         = "daily-efs-backup"
    target_vault_name = aws_backup_vault.moodle.name
    schedule          = "cron(0 2 ? * * *)"
    # 02:00 UTC daily.
    # AWS cron format: cron(minute hour day-of-month month day-of-week year)
    # CRITICAL: either day-of-month OR day-of-week MUST be ? -
    # never both *. cron(0 2 * * * *) is rejected at apply time
    # with InvalidParameterValue.

    lifecycle {
      delete_after = var.efs_backup_retention_days
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-moodle-backup-plan"
  }
}

resource "aws_backup_selection" "moodle_efs" {
  name         = "${var.project_name}-${var.environment}-moodle-efs-selection"
  iam_role_arn = var.backup_role_arn
  plan_id      = aws_backup_plan.moodle.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "BackupPolicy"
    value = "daily-7d"
  }
  # Tag-based selection - picks any resource tagged
  # BackupPolicy = "daily-7d". The EFS file system created in
  # T-016 carries this tag. Forward-compatible: Phase 2 resources
  # with the same tag get included automatically with no Backup
  # resource changes.
}
