#checkov:skip=CKV_AWS_18: Bucket access logging not enabled in Phase 1; revisit if Phase 2 audit posture requires it.
#checkov:skip=CKV_AWS_144: Cross-region replication intentionally disabled in Phase 1 to control costs. CloudTrail logs locally durable via versioning + object-lock; revisit Phase 2.
#checkov:skip=CKV_AWS_145: SSE-S3 (aws/s3) used per CLAUDE.md hard rule #3; CMK introduced in Phase 2 only for payment data isolation.
#checkov:skip=CKV2_AWS_62: Event notifications not required in Phase 1; bootstrap is human-driven.
#tfsec:ignore:aws-s3-enable-bucket-logging Bucket access logging not enabled in Phase 1; revisit if Phase 2 audit posture requires it.
resource "aws_s3_bucket" "cloudtrail" {
  bucket              = "wirfo-moodle-cloudtrail-${data.aws_caller_identity.current.account_id}"
  object_lock_enabled = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

# tfsec:ignore:aws-s3-encryption-customer-key No CMK in Phase 1 per CLAUDE.md rule 3; revisit Phase 2.
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-1:${data.aws_caller_identity.current.account_id}:trail/moodle_mgmt"
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-1:${data.aws_caller_identity.current.account_id}:trail/moodle_mgmt"
          }
        }
      }
    ]
  })
}

#checkov:skip=CKV_AWS_35: CloudTrail trail at-rest encryption requires CMK; per CLAUDE.md rule 3 no CMKs in Phase 1; S3 destination bucket is SSE-S3 encrypted; revisit Phase 2.
#checkov:skip=CKV2_AWS_10: CloudWatch Logs integration intentionally not configured in Phase 1; logs go to S3 with object-lock for tamper resistance per design.md §6.1; revisit Phase 2.
#checkov:skip=CKV_AWS_252: SNS notifications on the trail itself not required in Phase 1; CloudTrail is for tamper-resistant historical evidence, not real-time alerting. Real-time threat detection is GuardDuty's job (T-025); per-log-file SNS notifications would be high-volume noise. Revisit Phase 2 if needed.
# tfsec:ignore:aws-cloudtrail-ensure-cloudwatch-integration CloudWatch Logs integration intentionally not configured in Phase 1; logs go to S3 with object-lock for tamper resistance. Revisit Phase 2 if log query / alerting needs require it.
# tfsec:ignore:aws-cloudtrail-enable-at-rest-encryption No CMK for trail payload encryption in Phase 1 per CLAUDE.md rule 3; S3 destination bucket is SSE-S3 encrypted; CMK for trail introduced in Phase 2 alongside payment data isolation.
resource "aws_cloudtrail" "moodle_mgmt" {
  name                          = "moodle_mgmt"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  include_global_service_events = true
  is_organization_trail         = false

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Filter required by the schema - empty {} matches all objects
    filter {}
  }
}
