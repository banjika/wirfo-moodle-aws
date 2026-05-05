variable "project_name" {
  type        = string
  description = "Resource-name prefix and Project tag value."
}

variable "environment" {
  type        = string
  description = "Logical environment name; Environment tag value."
}

variable "vpc_id" {
  type        = string
  description = "VPC in which to create the security groups. Passed from module.network.vpc_id."

  validation {
    condition     = startswith(var.vpc_id, "vpc-")
    error_message = "vpc_id must begin with 'vpc-'."
  }
}
