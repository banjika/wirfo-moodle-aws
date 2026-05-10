# Phase 1 deferrals on EFS:
#   - CMK at rest: CLAUDE.md hard rule #3 (no CMK in Phase 1); uses aws/elasticfilesystem default.
#     CMK introduced in Phase 2 for payment data isolation.
#   - Second mount target (AZ-b): CLAUDE.md hard rule #2 (single-AZ pilot).
#     Phase 3 adds aws_efs_mount_target.az_b additively — no replacement of this resource.
#checkov:skip=CKV_AWS_184: Phase 1 no CMK per CLAUDE.md hard rule #3; uses aws/elasticfilesystem default key. CMK introduced in Phase 2 for payment data isolation.
resource "aws_efs_file_system" "moodledata" {
  # Idempotency token — prevents duplicate file system creation
  # if the apply is interrupted and retried.
  creation_token = "${var.project_name}-${var.environment}-moodledata"

  encrypted  = true
  kms_key_id = null
  # Explicit null — uses aws/elasticfilesystem default per CLAUDE.md hard rule #3 (no CMK in Phase 1).

  throughput_mode = var.efs_throughput_mode
  # "bursting" in Phase 1 — cheaper than "elastic" at low traffic (requirements §6).
  # Bursting gives free baseline throughput proportional to stored GB.
  performance_mode = "generalPurpose"
  # General-purpose mode is fine for Moodle file workload.
  # Max-IO mode is for high-parallelism workloads (data lakes).

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
    # Files not accessed for 30 days move to Infrequent Access tier (~90% cheaper than Standard).
    # Moodle's access pattern is write-once-read-rarely for user uploads.
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-moodledata"
    BackupPolicy = "daily-7d"
    # T-017's AWS Backup selection picks resources by this tag.
    # Tag here so T-017's selection works without modifying this resource.
  }

  lifecycle {
    prevent_destroy = true
    # Data loss is unrecoverable. EFS has no AWS-side deletion_protection equivalent —
    # Terraform-side prevent_destroy is the only guard. AWS Backup (T-017) is the recovery story.
  }
}

resource "aws_efs_mount_target" "az_a" {
  file_system_id = aws_efs_file_system.moodledata.id
  subnet_id      = var.efs_subnet_id
  # Singular — Phase 1 uses AZ-a only per CLAUDE.md hard rule #2.
  # Phase 3 adds a second resource aws_efs_mount_target.az_b in the AZ-b private subnet.
  security_groups = [var.efs_sg_id]
  # NFS (port 2049) ingress from web_sg only, per T-011 §4 matrix.
}

resource "aws_efs_file_system_policy" "moodledata" {
  file_system_id = aws_efs_file_system.moodledata.id

  # Explicit Deny — "deny all EFS actions on this file system, from any principal,
  # when the connection is not using TLS." AWS IAM evaluates explicit deny before allow,
  # so this overrides any other policy.
  # CLAUDE.md hard rule #10 (HTTPS/TLS only) implementation for EFS — analogue to
  # RDS's rds.force_ssl=1 (T-014) and ElastiCache's transit_encryption_mode="required" (T-015).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
     {
        Sid       = "AllowTLSAccessFromMoodleEC2"
        Effect    = "Allow"
        Principal = { AWS = var.ec2_role_arn }
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientRootAccess",
          "elasticfilesystem:ClientWrite",
        ]
        Resource = aws_efs_file_system.moodledata.arn
        Condition = {
          Bool = { "aws:SecureTransport" = "true" }
        }
      },
      {
        Sid       = "DenyNonTLSAccess"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "*"
        Resource  = aws_efs_file_system.moodledata.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
