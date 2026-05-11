variable "project_name" {
  type        = string
  description = "Resource-name prefix and Project tag value."
}

variable "environment" {
  type        = string
  description = "Logical environment name; Environment tag value."
}

variable "cache_subnet_ids" {
  type        = list(string)
  description = "At least 2 private subnet IDs across different AZs. The subnet group must be multi-AZ-capable (AWS API requirement); the replication group is single-node via num_node_groups = 1, replicas_per_node_group = 0, multi_az_enabled = false."

  validation {
    condition     = length(var.cache_subnet_ids) >= 2
    error_message = "cache_subnet_ids must contain at least 2 subnet IDs (AWS API requires a multi-AZ-capable subnet group)."
  }
}

variable "cache_sg_id" {
  type        = string
  description = "Security group ID for the ElastiCache Valkey replication group."

  validation {
    condition     = startswith(var.cache_sg_id, "sg-")
    error_message = "cache_sg_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "cache_node_type" {
  type        = string
  description = "ElastiCache node type (e.g. cache.t4g.micro)."
}

variable "cache_engine_version" {
  type        = string
  description = "Valkey engine version string with dot (e.g. '7.2'). Note: the parameter group family uses a different format ('valkey7', no dot - see main.tf comment)."
}
