/**
 * # Azure Resource Group Module - Variables
 *
 * Input variables for the resource group module.
 */

variable "name" {
  description = "Name of the resource group. If null, a name should be provided by Terragrunt using the naming module."
  type        = string
  default     = null

  validation {
    condition     = var.name == null ? true : length(var.name) >= 1 && length(var.name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }

  validation {
    condition     = var.name == null ? true : can(regex("^[a-zA-Z0-9-_.()]+$", var.name))
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

# Variables for naming module
variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "centric"
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

variable "customer" {
  description = "Customer name (used in resource naming for multi-tenant resources)"
  type        = string
  default     = null
} 