variable "project_name" {
  type        = string
  description = "Resource-name prefix and Project tag value."
}

variable "environment" {
  type        = string
  description = "Logical environment name; Environment tag value."
}

variable "efs_subnet_id" {
  type        = string
  description = "Private subnet ID for the EFS mount target ENI. SINGULAR — Phase 1 uses AZ-a only per CLAUDE.md hard rule #2. Phase 3 adds a second mount target in AZ-b without modifying this variable."

  validation {
    condition     = startswith(var.efs_subnet_id, "subnet-")
    error_message = "efs_subnet_id must be a valid subnet ID starting with 'subnet-'."
  }
}

variable "efs_sg_id" {
  type        = string
  description = "Security group ID for the EFS mount target. Allows NFS (TCP 2049) ingress from web_sg only."

  validation {
    condition     = startswith(var.efs_sg_id, "sg-")
    error_message = "efs_sg_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "efs_throughput_mode" {
  type        = string
  description = "EFS throughput mode. 'bursting' in Phase 1 — cheaper than 'elastic' at low traffic (requirements §6)."

  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.efs_throughput_mode)
    error_message = "efs_throughput_mode must be one of: bursting, provisioned, elastic."
  }
}

variable "efs_backup_retention_days" {
  type        = number
  description = "Days to retain EFS backups in the AWS Backup vault. Phase 1 default is 7 (per requirements §2.1 RPO 24h with 7-day retention window for headroom)."

  validation {
    condition     = var.efs_backup_retention_days >= 1 && var.efs_backup_retention_days <= 35
    error_message = "efs_backup_retention_days must be between 1 and 35 days."
  }
}

variable "backup_role_arn" {
  type        = string
  description = "ARN of the IAM role assumed by AWS Backup. Created in modules/security (T-012); first consumer is T-017's aws_backup_selection."

  validation {
    condition     = startswith(var.backup_role_arn, "arn:aws:iam::")
    error_message = "backup_role_arn must be a valid IAM role ARN."
  }
}
