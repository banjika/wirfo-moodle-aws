# GuardDuty account-wide threat detection - one detector per opted-in region.
#
# Terraform requires statically declared provider configurations; provider
# aliases cannot be constructed dynamically inside for_each (static-provider
# constraint). Each detector is therefore a separate resource block. Verbose
# but Terraform-correct. Toggle all 17 via var.enable_guardduty.
#
# eu-west-1 uses the default provider (no alias) to avoid a duplicate
# provider configuration. All others reference their regional alias declared
# in versions.tf.
#
# Design deviation from design.md §2.8: the spec described for_each over
# aws_regions inside modules/observability, but Terraform's static-provider
# requirement makes that pattern non-functional. Detectors live at the workload
# root instead. The observability module is unchanged structurally.

# Suppression rationale for all 17 aws_guardduty_detector resources below:
#   CKV2_AWS_58 - S3 protection uses account default; explicit enablement via
#                 datasources block requires one aws_guardduty_detector_feature
#                 resource per region (17 extra). Phase 2 via delegated admin.
#   CKV2_AWS_3  - Rule wants GuardDuty wired to an AWS Organizations delegated
#                 admin. Phase 1 is single-account; no AWS Organizations.
#                 Org-level GuardDuty is a Phase 2 multi-account concern
#                 per design.md §2.8.
#checkov:skip=CKV2_AWS_58: see suppression rationale above - applies to all 17 detectors.
#checkov:skip=CKV2_AWS_3: see suppression rationale above - applies to all 17 detectors.
resource "aws_guardduty_detector" "eu_west_1" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "us_east_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.us_east_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "ap_northeast_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.ap_northeast_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "ap_northeast_2" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.ap_northeast_2
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "ap_northeast_3" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.ap_northeast_3
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "ap_south_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.ap_south_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "ap_southeast_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.ap_southeast_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "ap_southeast_2" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.ap_southeast_2
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "ca_central_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.ca_central_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "eu_central_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.eu_central_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "eu_north_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.eu_north_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "eu_west_2" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.eu_west_2
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "eu_west_3" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.eu_west_3
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "sa_east_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.sa_east_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "us_east_2" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.us_east_2
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "us_west_1" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.us_west_1
  enable   = true
}

#checkov:skip=CKV2_AWS_58: see eu_west_1 note above.
resource "aws_guardduty_detector" "us_west_2" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.us_west_2
  enable   = true
}
