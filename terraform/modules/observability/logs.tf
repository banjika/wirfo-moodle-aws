# ---------------------------------------------------------------------
# CloudWatch Log Groups for Moodle
# ---------------------------------------------------------------------
# Three log groups capture EC2-side logs via the CloudWatch Agent
# (configured by user-data in T-018), plus one for the Synthetics
# canary (T-024). Names are hardcoded (not variables) because they
# are stable identifiers referenced by user-data, IAM policies,
# and the canary configuration. Phase 1 cost stance: 30-day
# retention. Phase 2 may extend for compliance.
# All log groups use AWS-managed encryption (kms_key_id = null,
# uses aws/logs default) - Phase 1 hard rule #3 (no CMKs).
# ---------------------------------------------------------------------

#checkov:skip=CKV_AWS_158: Phase 1 hard rule #3 - no CMKs. Uses AWS-managed aws/logs encryption. Phase 2 may add aws/logs CMK.
#checkov:skip=CKV_AWS_338: 30-day retention is deliberate Phase 1 cost stance per requirements §4 / design.md §3. Extended retention deferred to Phase 2 compliance review.
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "app" {
  name              = "/moodle/app"
  retention_in_days = var.log_retention_days
  kms_key_id        = null

  tags = {
    Name = "${var.project_name}-${var.environment}-app-logs"
  }
}

#checkov:skip=CKV_AWS_158: Phase 1 hard rule #3 - no CMKs. Uses AWS-managed aws/logs encryption. Phase 2 may add aws/logs CMK.
#checkov:skip=CKV_AWS_338: 30-day retention is deliberate Phase 1 cost stance per requirements §4 / design.md §3. Extended retention deferred to Phase 2 compliance review.
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "web" {
  name              = "/moodle/web"
  retention_in_days = var.log_retention_days
  kms_key_id        = null

  tags = {
    Name = "${var.project_name}-${var.environment}-web-logs"
  }
}

#checkov:skip=CKV_AWS_158: Phase 1 hard rule #3 - no CMKs. Uses AWS-managed aws/logs encryption. Phase 2 may add aws/logs CMK.
#checkov:skip=CKV_AWS_338: 30-day retention is deliberate Phase 1 cost stance per requirements §4 / design.md §3. Extended retention deferred to Phase 2 compliance review.
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "system" {
  name              = "/moodle/system"
  retention_in_days = var.log_retention_days
  kms_key_id        = null

  tags = {
    Name = "${var.project_name}-${var.environment}-system-logs"
  }
}

#checkov:skip=CKV_AWS_158: Phase 1 hard rule #3 - no CMKs. Uses AWS-managed aws/logs encryption. Phase 2 may add aws/logs CMK.
#checkov:skip=CKV_AWS_338: 30-day retention is deliberate Phase 1 cost stance per requirements §4 / design.md §3. Extended retention deferred to Phase 2 compliance review.
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "canary" {
  name              = "/aws/canary/moodle"
  retention_in_days = var.log_retention_days
  kms_key_id        = null

  tags = {
    Name = "${var.project_name}-${var.environment}-canary-logs"
  }
}

# ---------------------------------------------------------------------
# SSM parameter holding the CloudWatch Agent JSON config
# ---------------------------------------------------------------------
# T-018's user-data fetches this on first boot via
#   aws ssm get-parameter --name /moodle/cloudwatch-agent/config
# and feeds it to amazon-cloudwatch-agent-ctl. Storing the config
# in SSM (not embedded in user-data) lets us update the CW Agent's
# config without redeploying the EC2 instance - just update the
# parameter and run 'amazon-cloudwatch-agent-ctl -a fetch-config'
# via SSM Run Command on the instance.
#
# Config covers:
#   - Metrics: CPU credits, memory, disk, swap
#   - Logs: Apache access/error → /moodle/web; PHP error log +
#     Moodle log → /moodle/app; syslog/fail2ban → /moodle/system
# ---------------------------------------------------------------------
#checkov:skip=CKV2_AWS_34: SSM type = "String" not "SecureString". CW Agent config has no secrets - only metric paths and log group names. SecureString would require kms:Decrypt on the EC2 instance role for zero security benefit.
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name        = "/moodle/cloudwatch-agent/config"
  description = "CloudWatch Agent JSON configuration for Moodle EC2 instance. Consumed by user-data on first boot."
  type        = "String"
  # SecureString would require the EC2 instance role to have
  # kms:Decrypt on the parameter's KMS key. The CW Agent config
  # contains no secrets (just metric/log paths) so String is fine.
  # Phase 2 may switch to SecureString if any sensitive endpoints
  # are added.

  tier = "Standard"
  # Standard tier supports parameters up to 4 KB. Our CW Agent
  # config is ~1.5 KB. Standard is free; Advanced is $0.05/month/
  # parameter.

  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "root"
    }

    metrics = {
      namespace = "Moodle/${var.environment}"

      metrics_collected = {
        cpu = {
          measurement                 = ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"]
          metrics_collection_interval = 60
          totalcpu                    = true
        }

        disk = {
          measurement                 = ["used_percent", "inodes_free"]
          metrics_collection_interval = 60
          resources                   = ["/"]
        }

        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 60
        }

        swap = {
          measurement                 = ["swap_used_percent"]
          metrics_collection_interval = 60
        }
      }
    }

    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path        = "/var/log/apache2/access.log"
              log_group_name   = aws_cloudwatch_log_group.web.name
              log_stream_name  = "{instance_id}/access"
              timestamp_format = "%d/%b/%Y:%H:%M:%S %z"
            },
            {
              file_path        = "/var/log/apache2/error.log"
              log_group_name   = aws_cloudwatch_log_group.web.name
              log_stream_name  = "{instance_id}/error"
              timestamp_format = "%a %b %d %H:%M:%S.%f %Y"
            },
            {
              file_path        = "/var/log/php_errors.log"
              log_group_name   = aws_cloudwatch_log_group.app.name
              log_stream_name  = "{instance_id}/php-errors"
              timestamp_format = "%d-%b-%Y %H:%M:%S %Z"
            },
            {
              file_path        = "/var/moodledata/logs/moodle.log"
              log_group_name   = aws_cloudwatch_log_group.app.name
              log_stream_name  = "{instance_id}/moodle"
              timestamp_format = "%Y-%m-%d %H:%M:%S"
            },
            {
              file_path        = "/var/log/syslog"
              log_group_name   = aws_cloudwatch_log_group.system.name
              log_stream_name  = "{instance_id}/syslog"
              timestamp_format = "%b %d %H:%M:%S"
            },
            {
              file_path        = "/var/log/fail2ban.log"
              log_group_name   = aws_cloudwatch_log_group.system.name
              log_stream_name  = "{instance_id}/fail2ban"
              timestamp_format = "%Y-%m-%d %H:%M:%S,%f"
            }
          ]
        }
      }
    }
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-cwagent-config"
  }
}
