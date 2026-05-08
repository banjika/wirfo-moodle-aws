locals {
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# 1: EC2 CPU > 80% for 5 min.
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-ec2-cpu-high"
  alarm_description   = "EC2 CPU utilization above 80% for 5 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}

# 2: EC2 CPU credits < ~20% of t4g.small maximum (576 credits).
# t4g.small earns 24 credits/hour; max bank = 576. Threshold 100 ≈ 17%.
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_credit_low" {
  alarm_name          = "${var.project_name}-${var.environment}-ec2-cpu-credit-low"
  alarm_description   = "EC2 CPU credit balance below 100 (roughly 17% of t4g.small max 576 credits)."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUCreditBalance"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}

# 3: EC2 status check failed.
# Separate from the Auto Recovery alarm in the compute module.
# Auto Recovery acts on StatusCheckFailed_System (hardware faults only).
# This alarm catches StatusCheckFailed (both system + instance) and pages the operator.
resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  alarm_name          = "${var.project_name}-${var.environment}-ec2-status-check"
  alarm_description   = "EC2 status check failed. Auto Recovery may be in progress; manual intervention may be required."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}

# 4: Disk > 85% — CW Agent custom metric (namespace Moodle/<env>).
# Missing data = breaching: no CW Agent data means the agent may have stopped.
resource "aws_cloudwatch_metric_alarm" "ec2_disk_high" {
  alarm_name          = "${var.project_name}-${var.environment}-ec2-disk-high"
  alarm_description   = "Root disk utilization above 85%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "Moodle/${var.environment}"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "breaching"

  dimensions = {
    path = "/"
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}

# 5: RDS connections > 80% of max.
# db.t4g.small (2 GB RAM): max_connections ≈ floor(2147483648 / 9531392) = 225.
# 80% of 225 ≈ 180; using 170 as a conservative threshold.
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-connections-high"
  alarm_description   = "RDS connection count above 170 (~80% of db.t4g.small max ~225)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 170
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}

# 6: RDS free storage < 15% of max_allocated_storage (200 GB).
# 200 GB × 15% = 30 GB = 32,212,254,720 bytes.
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-storage-low"
  alarm_description   = "RDS free storage below 30 GB (15% of 200 GB max_allocated_storage)."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 32212254720
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}

# 7: RDS CPU > 80% for 10 min (2 consecutive 5-min periods).
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  alarm_description   = "RDS CPU utilization above 80% for 10 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}

# 8: ElastiCache evictions > 0.
# Any eviction signals memory pressure — cache.t4g.micro has 500 MB;
# sustained evictions degrade Moodle session and MUC performance.
resource "aws_cloudwatch_metric_alarm" "cache_evictions" {
  alarm_name          = "${var.project_name}-${var.environment}-cache-evictions"
  alarm_description   = "ElastiCache evictions detected. Cache may be memory-constrained; consider upgrading node size."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = var.cache_cluster_id
    CacheNodeId    = "0001"
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}

# 9: Synthetics canary success rate < 100%.
# References aws_synthetics_canary.moodle_login directly; both resources live
# in this module (T-024), so no var.canary_name passthrough is needed.
resource "aws_cloudwatch_metric_alarm" "canary_failed" {
  alarm_name          = "${var.project_name}-${var.environment}-canary-failed"
  alarm_description   = "Synthetics canary login check failing. Moodle login page may be unreachable."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SuccessPercent"
  namespace           = "CloudWatchSynthetics"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  treat_missing_data  = "breaching"

  dimensions = {
    CanaryName = aws_synthetics_canary.moodle_login.name
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions
}
