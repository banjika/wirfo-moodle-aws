data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --------------------------------------------------------------------------
# EC2 instance role (8 resources)
# --------------------------------------------------------------------------

resource "aws_iam_role" "moodle_ec2" {
  # Name must match the iam:PassRole target in bootstrap/iam_deploy.tf exactly.
  name = "moodle_ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-moodle-ec2-role"
  }
}

resource "aws_iam_role_policy_attachment" "moodle_ec2_ssm" {
  role       = aws_iam_role.moodle_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "moodle_ec2_cw_agent" {
  role       = aws_iam_role.moodle_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "moodle_ec2_secrets" {
  name = "secrets-manager-read"
  role = aws_iam_role.moodle_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:moodle/*"
    }]
  })
}

#tfsec:ignore:aws-iam-no-policy-wildcards Resource=* is required for SES SendEmail; the Condition (ses:FromAddress *@wirfoncloud.com) is the access constraint. Same false-positive family as T-010/T-011 — scanner pattern check does not inspect Condition blocks.
resource "aws_iam_role_policy" "moodle_ec2_ses" {
  name = "ses-send"
  role = aws_iam_role.moodle_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
      Condition = {
        StringLike = {
          "ses:FromAddress" = "*@wirfoncloud.com"
        }
      }
    }]
  })
}

#tfsec:ignore:aws-iam-no-policy-wildcards Resource=* is required for AWS-managed KMS keys (aws/secretsmanager, aws/rds) whose ARNs the account does not control; access restricted by kms:ViaService condition. Same false-positive family as T-010/T-011 — scanner pattern check does not inspect Condition blocks.
resource "aws_iam_role_policy" "moodle_ec2_kms" {
  name = "kms-decrypt-via-service"
  role = aws_iam_role.moodle_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "kms:ViaService" = [
            "secretsmanager.${data.aws_region.current.name}.amazonaws.com",
            "rds.${data.aws_region.current.name}.amazonaws.com",
          ]
        }
      }
    }]
  })
}

#tfsec:ignore:aws-iam-no-policy-wildcards Resource=* is required for CloudWatch PutMetricData; access restricted to Moodle/* sub-namespaces via cloudwatch:namespace StringLike condition. Same false-positive family as T-010/T-011 — scanner pattern check does not inspect Condition blocks.
resource "aws_iam_role_policy" "moodle_ec2_cw_metrics" {
  name = "cw-metrics-moodle-namespace"
  role = aws_iam_role.moodle_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "cloudwatch:PutMetricData"
      Resource = "*"
      Condition = {
        StringLike = {
          "cloudwatch:namespace" = "Moodle/*"
        }
      }
    }]
  })
}

resource "aws_iam_instance_profile" "moodle_ec2" {
  name = aws_iam_role.moodle_ec2.name
  role = aws_iam_role.moodle_ec2.name

  tags = {
    Name = "${var.project_name}-${var.environment}-moodle-ec2-profile"
  }
}

# --------------------------------------------------------------------------
# AWS Backup role (3 resources)
# --------------------------------------------------------------------------

resource "aws_iam_role" "aws_backup" {
  name = "${var.project_name}-${var.environment}-aws-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-aws-backup-role"
  }
}

resource "aws_iam_role_policy_attachment" "aws_backup_main" {
  role       = aws_iam_role.aws_backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "aws_backup_restore" {
  role       = aws_iam_role.aws_backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}
