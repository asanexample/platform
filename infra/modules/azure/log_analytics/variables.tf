/**
 * # Log Analytics Variables
 * 
 * Variables for the Azure Log Analytics module
 */

# ---------------------------------------------------------------------------------------------------------------------
# NAMING AND GENERAL VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "prefix" {
  description = "The prefix to use for generated resource names"
  type        = string
  default     = "centric"
  validation {
    condition     = length(var.prefix) <= 10
    error_message = "The prefix can be at most 10 characters."
  }
}

variable "customer" {
  description = "The customer identifier"
  type        = string
  default     = null
  validation {
    condition     = var.customer == null ? true : length(var.customer) <= 15
    error_message = "The customer identifier can be at most 15 characters."
  }
}

variable "environment" {
  description = "The environment (e.g., dev, test, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "region_abbv" {
  description = "The abbreviated region name"
  type        = string
  default     = "weu"
}

# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE DETAILS
# ---------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "The name of the Log Analytics workspace. If null, the name will be auto-generated using the prefix, environment, and region_abbv values."
  type        = string
  default     = null
  validation {
    condition     = var.name == null ? true : length(var.name) >= 4 && length(var.name) <= 63
    error_message = "Log Analytics workspace name must be between 4 and 63 characters."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "The resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  validation {
    condition = contains([
      "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast",
      "brazilsouth", "brazilsoutheast",
      "canadacentral", "canadaeast",
      "centralindia", "centralus",
      "eastasia", "eastus", "eastus2",
      "francecentral", "francesouth",
      "germanynorth", "germanywestcentral",
      "japaneast", "japanwest",
      "koreacentral", "koreasouth",
      "northcentralus", "northeurope", "norwayeast", "norwaywest",
      "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "swedencentral", "switzerlandnorth", "switzerlandwest",
      "uaecentral", "uaenorth", "uksouth", "ukwest", "usnorth", "uswest", "uswest2", "uswest3",
      "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3"
    ], var.location)
    error_message = "Invalid Azure location. Please check available locations."
  }
}

variable "sku" {
  description = "The SKU of the Log Analytics workspace (PerGB2018, Free, PerNode, Premium, Standard, Standalone, Unlimited, CapacityReservation)"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["PerGB2018", "Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation"], var.sku)
    error_message = "SKU must be one of PerGB2018, Free, PerNode, Premium, Standard, Standalone, Unlimited, or CapacityReservation."
  }
}

variable "retention_in_days" {
  description = "The number of days to retain data in the Log Analytics workspace (between 30 and 730)"
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "Retention days must be between 30 and 730 days."
  }
}

variable "daily_quota_gb" {
  description = "The daily ingestion quota in GB for the Log Analytics workspace"
  type        = number
  default     = null
}

variable "internet_ingestion_enabled" {
  description = "Whether internet ingestion is enabled for the Log Analytics workspace"
  type        = bool
  default     = true
}

variable "internet_query_enabled" {
  description = "Whether internet query is enabled for the Log Analytics workspace"
  type        = bool
  default     = true
}

variable "reservation_capacity_in_gb_per_day" {
  description = "The capacity reservation level in GB per day (only applies to CapacityReservation SKU)"
  type        = number
  default     = 0
}

variable "solution_plans" {
  description = "List of solution plans to deploy to the Log Analytics workspace"
  type = list(object({
    solution_name = string
  }))
  default = []
}

variable "diagnostic_settings" {
  description = "A list of diagnostic settings to create for the Log Analytics workspace"
  type = list(object({
    name                       = string
    log_analytics_workspace_id = string
    enabled_log_categories     = list(string)
    metric_categories          = list(string)
    log_retention_days         = number
  }))
  default = []
}

variable "linked_storage_accounts" {
  description = "Map of data source types to storage account IDs for linked storage accounts"
  type        = map(list(string))
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
} 