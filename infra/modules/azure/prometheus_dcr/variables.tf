/**
 * Variables for the Prometheus DCR module.
 */

variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "name" {
  description = "Optional base name for the DCR (e.g., 'dcr-prometheus'). Defaults will be generated if null."
  type        = string
  default     = null
  validation {
    condition     = var.name == null ? true : length(var.name) >= 3 && length(var.name) <= 63
    error_message = "The DCR name must be between 3 and 63 characters when provided."
  }
  validation {
    condition     = var.name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.name))
    error_message = "The DCR name can only include alphanumeric, hyphen, and underscore characters."
  }
}

variable "dce_name" {
  description = "Optional name for the Data Collection Endpoint (DCE). Defaults will be generated if null."
  type        = string
  default     = null
  validation {
    condition     = var.dce_name == null ? true : length(var.dce_name) >= 3 && length(var.dce_name) <= 63
    error_message = "The DCE name must be between 3 and 63 characters when provided."
  }
  validation {
    condition     = var.dce_name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.dce_name))
    error_message = "The DCE name can only include alphanumeric, hyphen, and underscore characters."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group to deploy the DCR and DCE in."
  type        = string
  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 63
    error_message = "Resource group name must be between 3 and 63 characters."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.()]+$", var.resource_group_name))
    error_message = "Resource group name can only include alphanumeric, hyphen, underscore, parentheses, and period characters."
  }
}

variable "location" {
  description = "The Azure region where the DCR and DCE will be deployed."
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
    error_message = "The location must be a valid Azure region name."
  }
}

variable "monitor_workspace_id" {
  description = "The resource ID of the Azure Monitor Workspace to send metrics to."
  type        = string
  validation {
    condition     = length(var.monitor_workspace_id) > 20
    error_message = "The monitor workspace ID must be a valid Azure resource ID."
  }
  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Monitor/accounts/[^/]+$", var.monitor_workspace_id))
    error_message = "The monitor workspace ID must be a valid Azure Monitor workspace resource ID format."
  }
}

variable "tags" {
  description = "A map of tags to apply to the DCR and DCE."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for key in keys(var.tags) : length(key) >= 1 && length(key) <= 512
    ]) || length(var.tags) == 0
    error_message = "Tag keys must be between 1 and 512 characters."
  }
  validation {
    condition = alltrue([
      for value in values(var.tags) : length(value) <= 256
    ]) || length(var.tags) == 0
    error_message = "Tag values must be 256 characters or less."
  }
} 