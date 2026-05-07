output "sns_topic_arn" {
  description = "ARN of the alarm SNS topic. Used by Phase 2 to add PagerDuty/OpsGenie subscriptions without recreating the topic."
  value       = aws_sns_topic.alarms.arn
}

output "app_log_group_name" {
  description = "/moodle/app log group name. Consumed by T-018 user-data CW Agent config and by Phase 2 application code pushing custom log events."
  value       = aws_cloudwatch_log_group.app.name
}

output "web_log_group_name" {
  description = "/moodle/web log group name. Captures Apache access/error logs via CW Agent."
  value       = aws_cloudwatch_log_group.web.name
}

output "system_log_group_name" {
  description = "/moodle/system log group name. Captures kernel/syslog/fail2ban via CW Agent."
  value       = aws_cloudwatch_log_group.system.name
}

output "canary_log_group_name" {
  description = "/aws/canary/moodle log group name. Receives Synthetics canary run logs (canary created in T-024)."
  value       = aws_cloudwatch_log_group.canary.name
}

output "cloudwatch_agent_config_parameter_name" {
  description = "SSM parameter holding the CW Agent JSON config. Consumed by T-018's user-data via 'aws ssm get-parameter'."
  value       = aws_ssm_parameter.cloudwatch_agent_config.name
}
