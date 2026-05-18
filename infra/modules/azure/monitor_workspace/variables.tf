/**
 * Variables for the Azure Monitor Workspace module.
 */

variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "name" {
  description = "The name of the Azure Monitor Workspace. If null, a name should be provided by Terragrunt using the naming module."
  type        = string
  default     = null

  validation {
    condition     = var.name == null ? true : length(var.name) >= 3 && length(var.name) <= 90
    error_message = "The name must be between 3 and 90 characters."
  }

  validation {
    condition     = var.name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.name))
    error_message = "The name can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the Azure Monitor Workspace in."
  type        = string
}

variable "location" {
  description = "The Azure region where the Azure Monitor Workspace will be deployed."
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to the Azure Monitor Workspace."
  type        = map(string)
  default     = {}
}

# Variables for naming module
variable "workload" {
  description = "Workload identifier for resource names"
  type        = string
  default     = "platform"
}

variable "environment" {
  description = "Environment name for resource naming (dev, test, staging, prod, ops)"
  type        = string
  default     = "dev"
}

variable "region_abbv" {
  description = "Abbreviation for Azure region (used in resource naming)"
  type        = string
  default     = "eus"
} 