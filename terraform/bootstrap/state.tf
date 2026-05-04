#checkov:skip=CKV_AWS_144: Cross-region replication intentionally disabled in Phase 1 to control costs. State recoverable via bootstrap re-apply. Revisit in Phase 2 per design.md.
#checkov:skip=CKV_AWS_18: Bucket access logging not enabled in Phase 1; will be revisited if Phase 2 audit posture requires it.
#tfsec:ignore:aws-s3-enable-bucket-logging Bucket access logging not enabled in Phase 1; revisit if Phase 2 audit posture requires it. (Same intent as #checkov:skip=CKV_AWS_18.)
resource "aws_s3_bucket" "tfstate" {
  bucket = "wirfo-moodle-tfstate-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# tfsec:ignore:aws-s3-encryption-customer-key No CMK in Phase 1 per CLAUDE.md rule 3; revisit Phase 2.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

#tfsec:ignore:aws-dynamodb-table-customer-key DynamoDB encrypted with aws/dynamodb default key per CLAUDE.md hard rule #3; CMK is Phase 2. (Same intent as #checkov:skip=CKV_AWS_119.)
resource "aws_dynamodb_table" "tflock" {
  name         = "wirfo-moodle-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}
