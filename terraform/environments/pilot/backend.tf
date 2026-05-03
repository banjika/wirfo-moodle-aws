# OPERATOR ACTION REQUIRED before the first `terraform init` without -backend=false:
#   Replace the literal string "<account-id>" in the bucket name below with your
#   12-digit AWS account ID (e.g. "wirfo-moodle-tfstate-123456789012").
#   The S3 bucket and DynamoDB table are created by the bootstrap config (T-004/T-008).
#
# Until that substitution is made, every `terraform init` in this directory
# MUST use -backend=false, otherwise Terraform will error on the bucket name.
terraform {
  backend "s3" {
    bucket         = "wirfo-moodle-tfstate-<account-id>"
    key            = "pilot/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "wirfo-moodle-tflock"
    encrypt        = true
  }
}
