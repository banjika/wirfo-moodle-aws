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
