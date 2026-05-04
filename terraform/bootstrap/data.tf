data "aws_caller_identity" "current" {}

# tflint-ignore: terraform_unused_declarations
data "aws_region" "current" {}

# tflint-ignore: terraform_unused_declarations
data "aws_route53_zone" "main" {
  # Trailing dot is intentional — canonical fully-qualified DNS form.
  name = "wirfoncloud.com."
}
