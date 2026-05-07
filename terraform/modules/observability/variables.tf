variable "project_name" {
  type        = string
  description = "Resource-name prefix and Project tag value."
}

variable "environment" {
  type        = string
  description = "Logical environment name; Environment tag value."
}

variable "alarm_email" {
  type        = string
  description = "Email address subscribed to the SNS alarm topic. Operator must click the confirmation link after first apply."
}

variable "instance_id" {
  type        = string
  description = "EC2 instance ID (module.compute.instance_id). Used as the InstanceId dimension on EC2 CloudWatch alarms."
}

variable "db_instance_identifier" {
  type        = string
  description = "RDS DB instance identifier (module.data.db_instance_identifier). Used as the DBInstanceIdentifier dimension on RDS alarms."
}

variable "cache_cluster_id" {
  type        = string
  description = "ElastiCache cluster ID (module.cache.cluster_id). Used as the CacheClusterId dimension on ElastiCache alarms."
}

variable "canary_name" {
  type        = string
  default     = ""
  description = "AWS Synthetics canary name (created in T-024). Pre-wired here so the canary-failed alarm exists before the canary itself. Empty default allows plan-testing before T-024 is built."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch log retention in days. Must be one of the AWS-supported retention values per requirements §4 / design.md §3 row 28."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the AWS-supported values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}
