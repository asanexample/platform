/**
 * # Azure Resource Group Module - Variables
 *
 * Input variables for the resource group module.
 */

variable "name" {
  description = "Name of the resource group"
  type        = string
  
  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.()]+$", var.name))
    error_message = "Resource group name can only include alphanumeric, hyphen, underscore, parentheses, and period characters."
  }
}

variable "location" {
  description = "Azure region where the resource group will be created"
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
    error_message = "The location must be a valid Azure region name."
  }
}

variable "tags" {
  description = "Tags to apply to the resource group"
  type        = map(string)
  default     = {}
} 