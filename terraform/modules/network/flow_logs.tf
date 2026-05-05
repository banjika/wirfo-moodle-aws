# No CMK on CloudWatch Logs in Phase 1 per CLAUDE.md hard rule #3; uses aws/logs default key. Phase 2 introduces CMKs for payment-data isolation only.
# 14-day retention is deliberate: flow logs are operational telemetry, not audit evidence. CloudTrail (90-day object-lock COMPLIANCE) covers that. Phase 2 may revisit.
#checkov:skip=CKV_AWS_158:No CMK in Phase 1 per CLAUDE.md hard rule #3; uses aws/logs default key.
#checkov:skip=CKV_AWS_338:Retention 14 days deliberate Phase 1 cost decision; CloudTrail covers audit needs.
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc-flow-logs/${aws_vpc.main.id}"
  retention_in_days = var.vpc_flow_log_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.project_name}-${var.environment}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-flow-logs-role"
  }
}

# False positive: tfsec sees the ":*" ARN suffix as a wildcard, but the resource is a
# fully-qualified log-group ARN + sub-resource match required by AWS for log stream access.
# Removing ":*" causes AccessDenied at runtime; Resource: "*" is NOT used anywhere here.
#tfsec:ignore:aws-iam-no-policy-wildcards
resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      # Both the log group ARN and the ":*" suffix are required: the bare ARN
      # covers group-level actions; ":*" covers log stream sub-resources.
      Resource = [
        aws_cloudwatch_log_group.vpc_flow_logs.arn,
        "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      ]
    }]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-flow-log"
  }
}
