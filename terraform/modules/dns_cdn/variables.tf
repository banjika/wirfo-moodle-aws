variable "project_name" {
  type        = string
  description = "Project identifier used in resource names and tags."
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., pilot) used in resource names and tags."
}

variable "domain_name" {
  type        = string
  description = "Public FQDN for the Moodle instance (e.g., academy.wirfoncloud.com). Used as the CloudFront alias and ACM cert subject."
}

variable "origin_domain_name" {
  type        = string
  description = "EC2 EIP public DNS name (module.compute.eip_public_dns). CloudFront custom origin target."

  validation {
    condition     = length(var.origin_domain_name) > 0
    error_message = "origin_domain_name must not be empty."
  }
}

variable "dmarc_rua_address" {
  description = "RUA mailbox in the DMARC TXT record. Receives aggregate authentication failure reports."
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.dmarc_rua_address))
    error_message = "Must be a valid email address."
  }
}
