/**
 * Input variables for the Log Analytics Workspace module
 */

variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

# Required variables
variable "name" {
  description = "The name of the Log Analytics Workspace. If null, a name should be provided by Terragrunt using the naming module."
  type        = string
  default     = null

  validation {
    condition     = var.name == null ? true : length(var.name) >= 4 && length(var.name) <= 63
    error_message = "The name must be between 4 and 63 characters."
  }

  validation {
    condition     = var.name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.name))
    error_message = "The name can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "location" {
  description = "The Azure region where the Log Analytics Workspace will be created"
  type        = string

  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "centralus", "southcentralus",
      "northcentralus", "westcentralus", "westeurope", "northeurope",
      "southeastasia", "eastasia", "japaneast", "japanwest", "australiaeast",
      "australiasoutheast", "australiacentral", "brazilsouth", "southindia",
      "centralindia", "westindia", "canadacentral", "canadaeast", "uksouth",
      "ukwest", "koreacentral", "koreasouth", "francecentral", "southafricanorth",
      "uaenorth", "switzerlandnorth", "germanywestcentral", "norwayeast",
      "swedencentral", "qatarcentral", "brazilsoutheast"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group where the Log Analytics Workspace will be created"
  type        = string

  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "The resource group name must be between 1 and 90 characters."
  }
}

# Optional variables with defaults
variable "sku" {
  description = "The SKU of the Log Analytics Workspace (PerGB2018, Free, PerNode, Premium, Standard, Standalone, Unlimited, or CapacityReservation)"
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["PerGB2018", "Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation"], var.sku)
    error_message = "The SKU must be one of: PerGB2018, Free, PerNode, Premium, Standard, Standalone, Unlimited, or CapacityReservation."
  }
}

variable "retention_in_days" {
  description = "The number of days to retain logs in the Log Analytics Workspace"
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "The retention period must be between 30 and 730 days."
  }
}

variable "daily_quota_gb" {
  description = "The workspace daily quota for ingestion in GB. Must be a positive number or null."
  type        = number
  default     = null

  validation {
    condition     = var.daily_quota_gb == null ? true : var.daily_quota_gb >= 0
    error_message = "The daily_quota_gb value must be null or a non-negative number."
  }
}

variable "internet_ingestion_enabled" {
  description = "Whether to enable internet ingestion for the Log Analytics Workspace"
  type        = bool
  default     = true
}

variable "internet_query_enabled" {
  description = "Whether to enable internet query for the Log Analytics Workspace"
  type        = bool
  default     = true
}

variable "solution_plans" {
  description = "A list of solution plans to install on the Log Analytics Workspace"
  type = list(object({
    solution_name = string
    publisher     = optional(string, "Microsoft")
    product       = optional(string, null)
  }))
  default = []

  validation {
    condition = alltrue([
      for plan in var.solution_plans :
      contains([
        "ContainerInsights", "Security", "SecurityInsights", "AzureActivity",
        "AgentHealthAssessment", "DnsAnalytics", "KeyVaultAnalytics",
        "ServiceMap", "SQLAssessment", "Updates", "VMInsights"
      ], plan.solution_name)
    ])
    error_message = "Each solution plan must have a valid solution name."
  }
}

variable "diagnostic_settings" {
  description = "A list of diagnostic settings to create for the Log Analytics Workspace"
  type = list(object({
    name                       = string
    log_analytics_workspace_id = string
    enabled_log_categories     = list(string)
    metric_categories          = list(string)
    log_retention_days         = number
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to apply to the Log Analytics Workspace"
  type        = map(string)
  default     = {}
}

variable "role_assignments" {
  description = "A list of role assignments to create for the Log Analytics Workspace"
  type = list(object({
    principal_id         = string
    role_definition_name = string
    description          = optional(string, null)
  }))
  default = []

  validation {
    condition = alltrue([
      for assignment in var.role_assignments :
      length(assignment.role_definition_name) > 0
    ])
    error_message = "The role_definition_name cannot be an empty string."
  }
}

# Environment variables
variable "environment" {
  description = "The environment name (dev, prod, etc.)"
  type        = string
  default     = "dev"
}

variable "workload" {
  description = "The workload identifier to apply to resource names"
  type        = string
  default     = "platform"
}

variable "region_abbv" {
  description = "The abbreviated name of the Azure region"
  type        = string
  default     = "eus"
} 