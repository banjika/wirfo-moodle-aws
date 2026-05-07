# Phase 1: single SNS topic + email subscription for all CloudWatch alarms.
# PagerDuty/OpsGenie integration deferred to Phase 2.
#tfsec:ignore:aws-sns-topic-encryption-use-cmk
resource "aws_sns_topic" "alarms" {
  name              = "${var.project_name}-${var.environment}-alarms"
  kms_master_key_id = "alias/aws/sns"
  # AWS-managed key per Phase 1 hard rule #3 (no CMKs).

  tags = {
    Name = "${var.project_name}-${var.environment}-alarms"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
