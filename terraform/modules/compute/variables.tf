# --------------------------------------------------------------------------
# GROUP 1 — Identity & tags (from workload root)
# --------------------------------------------------------------------------

variable "project_name" {
  type        = string
  description = "Resource-name prefix and Project tag value."
}

variable "environment" {
  type        = string
  description = "Logical environment name; Environment tag value."
}

# --------------------------------------------------------------------------
# GROUP 2 — Instance configuration (from workload root variables)
# --------------------------------------------------------------------------

variable "instance_type" {
  type        = string
  description = "EC2 instance type. t4g.small (Graviton) for Phase 1 cost target of ~$80/month."
}

variable "root_volume_gb" {
  type        = number
  description = "Root EBS volume size in GiB. Minimum 30 GiB for Moodle + PHP + OS."
}

variable "domain_name" {
  type        = string
  description = "Public FQDN for the Moodle install, e.g., academy.wirfoncloud.com. Written to config.php wwwroot and Apache ServerName."
}

variable "moodle_admin_email" {
  type        = string
  description = "Initial Moodle admin account email. Passed to the CLI installer."
}

variable "aws_region" {
  type        = string
  description = "AWS region for EFS DNS name construction and Secrets Manager API calls in user-data."
}

# --------------------------------------------------------------------------
# GROUP 3 — Network (from module.network)
# --------------------------------------------------------------------------

variable "public_subnet_id" {
  type        = string
  description = "Public subnet ID for the EC2 instance. SINGULAR — AZ-a only per CLAUDE.md hard rules #1 (no NAT) and #2 (single-AZ pilot). Phase 3 moves EC2 behind ALB in a private subnet."

  validation {
    condition     = startswith(var.public_subnet_id, "subnet-")
    error_message = "public_subnet_id must be a valid subnet ID starting with 'subnet-'."
  }
}

# --------------------------------------------------------------------------
# GROUP 4 — Security (from module.security)
# --------------------------------------------------------------------------

variable "web_sg_id" {
  type        = string
  description = "Security group ID for the EC2 web tier. Ingress: CloudFront origin-facing prefix list on 80/443. Created in modules/security (T-011)."

  validation {
    condition     = startswith(var.web_sg_id, "sg-")
    error_message = "web_sg_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "ec2_instance_profile_name" {
  type        = string
  description = "IAM instance profile name for the EC2 instance. Grants SSM, CloudWatch Agent, Secrets Manager, and SES permissions. Created in modules/security (T-012)."
}

variable "db_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret containing DB credentials (username/password JSON). Read by user-data at first boot via the EC2 instance profile."

  validation {
    condition     = startswith(var.db_secret_arn, "arn:aws:secretsmanager:")
    error_message = "db_secret_arn must be a valid Secrets Manager ARN starting with 'arn:aws:secretsmanager:'."
  }
}

variable "admin_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret containing Moodle admin credentials (username/password JSON). Read by user-data at first boot via the EC2 instance profile."

  validation {
    condition     = startswith(var.admin_secret_arn, "arn:aws:secretsmanager:")
    error_message = "admin_secret_arn must be a valid Secrets Manager ARN starting with 'arn:aws:secretsmanager:'."
  }
}

# --------------------------------------------------------------------------
# GROUP 5 — Data (from module.data)
# --------------------------------------------------------------------------

variable "db_endpoint" {
  type        = string
  description = "RDS PostgreSQL endpoint in host:port format. Passed to the Moodle CLI installer and createdb."
}

variable "db_port" {
  type        = number
  description = "RDS PostgreSQL port. Typically 5432."
}

# --------------------------------------------------------------------------
# GROUP 6 — Cache (from module.cache)
# --------------------------------------------------------------------------

variable "cache_endpoint" {
  type        = string
  description = "ElastiCache Valkey primary endpoint hostname. TLS required; port 6379."
}

variable "cache_port" {
  type        = number
  description = "ElastiCache Valkey port. Typically 6379."
}

variable "cache_auth_token" {
  type        = string
  sensitive   = true
  description = "Valkey AUTH token for TLS-authenticated connections. Spec gap fix: design.md §2.3 lists cache_endpoint and cache_port but not cache_auth_token. Moodle requires it to populate session_redis_auth in config.php. Wired from module.cache.cache_auth_token in T-019."
}

# --------------------------------------------------------------------------
# GROUP 7 — Storage (from module.storage)
# --------------------------------------------------------------------------

variable "efs_id" {
  type        = string
  description = "EFS file system ID for the Moodle data directory. Mounted at /var/moodledata over TLS using the IAM instance profile. Created in modules/storage (T-016)."

  validation {
    condition     = startswith(var.efs_id, "fs-")
    error_message = "efs_id must be a valid EFS file system ID starting with 'fs-'."
  }
}
