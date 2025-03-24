variable "prefix" {
  description = "The prefix to use for all resources. Defaults to 'vip' if not specified."
  type        = string
  default     = "vip"
}

variable "customer" {
  description = "The customer name to use in resource naming. Optional for shared resources."
  type        = string
  default     = null
}

variable "environment" {
  description = "The environment (e.g., dev, preprod, prod, ops)."
  type        = string
  validation {
    condition     = contains(["dev", "preprod", "prod", "test", "stg", "ops"], var.environment)
    error_message = "Environment must be one of: dev, preprod, prod, test, stg, ops."
  }
}

variable "region_abbv" {
  description = "The abbreviated Azure region name (e.g., wus, eus, neu)."
  type        = string
  validation {
    condition     = length(var.region_abbv) <= 5
    error_message = "Region abbreviation should not be longer than 5 characters."
  }
}

variable "resource_type" {
  description = "Optional resource type for custom naming."
  type        = string
  default     = null
}

variable "custom_name" {
  description = "Optional custom name to override the generated name."
  type        = string
  default     = null
}

variable "unique_seed" {
  description = "Seed for unique naming generation"
  type        = string
  default     = ""
} 