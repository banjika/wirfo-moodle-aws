# ---------------------------------------------------------------------------
# Identity & tags
# ---------------------------------------------------------------------------

variable "project_name" {
  type        = string
  default     = "moodle-academy"
  description = "Resource-name prefix and Project tag value."
}

variable "environment" {
  type        = string
  default     = "pilot"
  description = "Logical environment name; Environment tag value."

  validation {
    condition     = contains(["pilot", "dev", "prod"], var.environment)
    error_message = "environment must be one of: pilot, dev, prod."
  }
}

variable "cost_center" {
  type        = string
  default     = "pilot"
  description = "CostCenter tag value."
}

variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "Workload region. Phase 1 is locked to eu-west-1."

  validation {
    condition     = var.aws_region == "eu-west-1"
    error_message = "Phase 1 is locked to eu-west-1. Update this constraint before expanding to additional regions."
  }
}

variable "github_repo" {
  type        = string
  default     = "banjika/wirfo-moodle-aws"
  description = "<owner>/<repo> used by bootstrap for OIDC trust scoping. Surfaced here for traceability."
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Primary IPv4 CIDR for the VPC."
}

variable "availability_zones" {
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
  description = "The two AZs provisioned at the VPC layer. Index 0 is the active AZ."
}

variable "active_availability_zone" {
  type        = string
  default     = "eu-west-1a"
  description = "Single AZ where Phase 1 actually runs workloads. Changing this post-deployment requires migrating every stateful resource (RDS, ElastiCache, EFS mount target)."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
  description = "Public subnet CIDRs, one per AZ. Index 0 = active AZ."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
  description = "Private subnet CIDRs, one per AZ. Index 0 = active AZ."
}

variable "vpc_flow_log_retention_days" {
  type        = number
  default     = 14
  description = "CloudWatch Logs retention period for VPC Flow Logs (days)."
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

variable "domain_name" {
  type        = string
  default     = "academy.wirfoncloud.com"
  description = "Public-facing FQDN served by CloudFront."
}

variable "dmarc_rua_address" {
  description = "RUA mailbox in the DMARC TXT record published by modules/dns_cdn. Receives aggregate authentication failure reports as machine-readable XML. No default — operator supplies a real, working email address in terraform.tfvars. Phase 2 may set up a domain-local mailbox via SES inbound + parser (e.g., dmarcian)."
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.dmarc_rua_address))
    error_message = "Must be a valid email address."
  }
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_type" {
  type        = string
  default     = "t4g.small"
  description = "EC2 instance type. Must be Graviton (arm64) to match the Ubuntu arm64 AMI."
}

variable "root_volume_gb" {
  type        = number
  default     = 30
  description = "EBS gp3 root volume size in GiB."
}

# ---------------------------------------------------------------------------
# Data (RDS)
# ---------------------------------------------------------------------------

variable "db_instance_class" {
  type        = string
  default     = "db.t4g.small"
  description = "RDS instance class."
}

variable "db_allocated_storage_gb" {
  type        = number
  default     = 20
  description = "Initial gp3 storage allocation for RDS (GiB)."
}

variable "db_max_allocated_storage_gb" {
  type        = number
  default     = 200
  description = "Storage autoscaling ceiling for RDS (GiB)."
}

variable "db_engine_version" {
  type        = string
  default     = "15.16"
  description = "Pinned PostgreSQL minor version. Review when PG 16 reaches GA in eu-west-1."
}

variable "db_backup_retention_days" {
  type        = number
  default     = 7
  description = "Automated backup retention period for RDS (days). RPO is 24 h; 7-day window covers PITR + headroom."
}

variable "db_master_username" {
  type        = string
  default     = "moodle_admin"
  description = "RDS master username."
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

variable "cache_node_type" {
  type        = string
  default     = "cache.t4g.micro"
  description = "ElastiCache Valkey node type."
}

variable "cache_engine_version" {
  type        = string
  default     = "7.2"
  description = "Valkey engine version. 7.2 is the cheapest current option versus Redis OSS."
}

# ---------------------------------------------------------------------------
# Storage (EFS)
# ---------------------------------------------------------------------------

variable "efs_throughput_mode" {
  type        = string
  default     = "bursting"
  description = "EFS throughput mode. Bursting is cheaper than elastic at Phase 1 scale."
}

variable "efs_backup_retention_days" {
  type        = number
  default     = 7
  description = "AWS Backup vault retention period for EFS daily snapshots (days)."
}

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

# REQUIRED - operator must supply
variable "moodle_admin_email" {
  type        = string
  description = "Initial Moodle admin email used at install time. Must match a verified SES recipient while the account is in the SES sandbox (see docs/runbooks/ses.md)."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$", var.moodle_admin_email))
    error_message = "moodle_admin_email must be a valid email address."
  }
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

# REQUIRED - operator must supply
variable "alarm_email" {
  type        = string
  description = "Single email subscription to the SNS alarm topic. PagerDuty/OpsGenie deferred to Phase 2."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$", var.alarm_email))
    error_message = "alarm_email must be a valid email address."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch Logs retention period for application log groups (days)."
}

variable "enable_synthetics_canary" {
  type        = bool
  default     = true
  description = "Toggle the CloudWatch Synthetics canary that probes /login/index.php every 5 minutes."
}

variable "enable_guardduty" {
  type        = bool
  default     = true
  description = "When true, enables GuardDuty in eu-west-1 and every other opted-in region in the account."
}

# ---------------------------------------------------------------------------
# Phase 3 toggles (all false in Phase 1)
# ---------------------------------------------------------------------------

variable "enable_high_availability" {
  type        = bool
  default     = false
  description = "Master HA flag. Reserved for Phase 3."
}

variable "rds_multi_az" {
  type        = bool
  default     = false
  description = "Independent RDS Multi-AZ flag. Reserved for Phase 3."
}

variable "enable_alb" {
  type        = bool
  default     = false
  description = "Independent ALB flag. Reserved for Phase 3."
}

variable "cache_cluster_mode" {
  type        = bool
  default     = false
  description = "Independent ElastiCache replica/cluster flag. Reserved for Phase 3."
}

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

variable "extra_tags" {
  type        = map(string)
  default     = {}
  description = "Caller-supplied tags merged on top of default_tags. Use for cost-allocation overrides."
}
