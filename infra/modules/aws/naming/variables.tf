variable "workload" {
  description = "The workload identifier used in resource naming (e.g., platform, data, hipaa, pci)."
  type        = string
  default     = "platform"

  validation {
    condition     = length(var.workload) >= 2 && length(var.workload) <= 10
    error_message = "Workload must be between 2 and 10 characters."
  }
}

variable "environment" {
  description = "The environment (e.g., dev, preprod, prod, ops)."
  type        = string
  validation {
    condition     = contains(["dev", "preprod", "prod", "test", "stg", "ops", "mgmt"], var.environment)
    error_message = "Environment must be one of: dev, preprod, prod, test, stg, ops, mgmt."
  }
}

variable "region_abbv" {
  description = "The abbreviated AWS region name (e.g., use1, usw2, euw1)."
  type        = string
  validation {
    condition     = length(var.region_abbv) <= 5
    error_message = "Region abbreviation should not be longer than 5 characters."
  }
}

variable "unique_seed" {
  description = "Seed for unique naming generation (used for globally unique resources like S3 buckets)."
  type        = string
  default     = ""
}
