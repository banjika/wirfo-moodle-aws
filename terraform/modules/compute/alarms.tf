# ---------------------------------------------------------------------
# EC2 Auto Recovery alarm
# ---------------------------------------------------------------------
# When the system status check fails (underlying hardware failure,
# not OS/application failure), CloudWatch triggers EC2 Auto Recovery.
# AWS terminates the instance and launches a replacement on different
# hardware, preserving:
#   - Instance ID
#   - EIP attachment (T-018)
#   - EBS volumes (root + any attached)
#   - ENI / private IP / public IP
# This is in-place recovery, not ASG-style replacement. Phase 3 may
# add ASG for true horizontal scaling on top of this.
# ---------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  alarm_name          = "${var.project_name}-${var.environment}-ec2-status-check-failed-system"
  alarm_description   = "EC2 system status check failed (underlying hardware) - triggers Auto Recovery."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  # If the metric stops being reported entirely (e.g., instance is
  # already replaced), don't fire the alarm. "missing" is the
  # conservative choice for recovery alarms.

  dimensions = {
    InstanceId = aws_instance.moodle.id
  }

  alarm_actions = [
    "arn:aws:automate:${var.aws_region}:ec2:recover"
    # Special ARN format AWS interprets as "trigger Auto Recovery."
    # The "automate" partition is reserved for AWS-native actions
    # like recover, stop, terminate, reboot.
  ]

  # No SNS notification action in P1 — the recovery happens
  # automatically without operator intervention. T-022 may add a
  # parallel SNS notification for awareness, but the recovery
  # action itself doesn't need it.

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-status-check-failed-system"
  }
}
