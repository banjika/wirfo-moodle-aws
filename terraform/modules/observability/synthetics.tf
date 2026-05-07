data "aws_caller_identity" "current" {}

data "archive_file" "canary" {
  type        = "zip"
  source_dir  = "${path.module}/canary/"
  output_path = "${path.module}/canary.zip"
}

# IAM role for the AWS Synthetics canary.
# Trust is on lambda.amazonaws.com — Synthetics runs canaries as managed Lambda
# functions; using synthetics.amazonaws.com is a common mistake that prevents
# the canary role assumption.
resource "aws_iam_role" "canary" {
  name = "${var.project_name}-${var.environment}-synthetics-canary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-synthetics-canary"
  }
}

resource "aws_iam_role_policy" "canary" {
  name = "${var.project_name}-${var.environment}-synthetics-canary"
  role = aws_iam_role.canary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CanaryArtifacts"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.canary_artifacts.arn}/*"]
      },
      {
        Sid    = "CanaryLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        # Trailing :* covers both log-group ARN (CreateLogStream) and
        # log-stream ARN (PutLogEvents) under the /aws/canary/ prefix.
        Resource = [
          "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/canary/*:*"
        ]
      },
      {
        Sid    = "CanaryMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        # cloudwatch:PutMetricData has no resource-level ARN; * is required.
        # Condition scopes it to the CloudWatchSynthetics namespace.
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "CloudWatchSynthetics"
          }
        }
      },
      {
        Sid      = "CanaryTracing"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments"]
        Resource = ["*"]
      }
    ]
  })
}

# S3 bucket for canary run artifacts (screenshots, HAR files, logs).
# Bucket name includes account ID for global uniqueness.
# Phase 1 cost stance: no access logging (writes are internal, audited via
# CloudTrail) and no cross-region replication (ephemeral 30-day artifacts).
#checkov:skip=CKV_AWS_18: Phase 1 cost stance — access logs only meaningful at production scale; canary writes are internal/audited via CloudTrail.
#checkov:skip=CKV_AWS_144: Phase 1 single-region; canary artifacts are ephemeral (30-day expiry); no DR concern.
#checkov:skip=CKV_AWS_145: Phase 1 hard rule #3 — no CMKs. Bucket uses SSE-S3 (AES256). Phase 2 may add CMK.
#checkov:skip=CKV2_AWS_62: Canary artifacts bucket is internal write-only storage; event notifications add no value at Phase 1 scale.
#tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "canary_artifacts" {
  bucket = "${var.project_name}-${var.environment}-canary-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-${var.environment}-canary-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES256) — no CMK per Phase 1 hard rule #3.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  # Versioning must exist before lifecycle rules referencing
  # noncurrent_version_expiration can be applied.
  depends_on = [aws_s3_bucket_versioning.canary_artifacts]

  rule {
    id     = "expire-canary-artifacts"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Canary name is capped at 21 characters (AWS Synthetics hard limit).
# "${var.project_name}-${var.environment}-moodle-login" = 33 chars with defaults —
# too long. "${var.environment}-moodle-login" = 18 chars with default "pilot". Fits cleanly.
#checkov:skip=CKV_AWS_117: aws_synthetics_canary is AWS-managed Lambda; VPC config is not applicable to this resource type.
resource "aws_synthetics_canary" "moodle_login" {
  name                 = "${var.environment}-moodle-login"
  artifact_s3_location = "s3://${aws_s3_bucket.canary_artifacts.id}/canary-artifacts/"
  execution_role_arn   = aws_iam_role.canary.arn

  # nodejs/node_modules/moodleLogin.js → handler = "moodleLogin.handler"
  handler  = "moodleLogin.handler"
  zip_file = data.archive_file.canary.output_path

  # Pinned for reproducibility. Verify against AWS Synthetics runtime support list
  # at https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Library_nodejs_puppeteer.html
  runtime_version = "syn-nodejs-puppeteer-15.0"

  start_canary = var.enable_synthetics_canary

  schedule {
    expression          = "rate(5 minutes)"
    duration_in_seconds = 0
    # 0 means run continuously on schedule, not "stop after N seconds".
  }

  run_config {
    timeout_in_seconds = 60
    memory_in_mb       = 1024
    active_tracing     = false

    environment_variables = {
      MOODLE_URL = "https://${var.domain_name}/login/index.php"
    }
  }

  # AWS run-data retention; independent of the /aws/canary log group
  # retention set by T-022's log_retention_days variable.
  success_retention_period = 7
  failure_retention_period = 31

  tags = {
    Name = "${var.project_name}-${var.environment}-moodle-canary"
  }
}
