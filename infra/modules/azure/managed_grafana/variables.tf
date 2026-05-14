/**
 * # Input Variables for Azure Managed Grafana Module
 *
 * This file defines all the variables used by the Azure Managed Grafana module.
 */

variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

# Required variables
variable "name" {
  description = "The name of the Azure Managed Grafana instance. If null, a name should be provided by Terragrunt using the naming module."
  type        = string
  default     = null
  
  validation {
    condition     = var.name == null ? true : length(var.name) >= 1 && length(var.name) <= 63
    error_message = "The name must be between 1 and 63 characters."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group where the Grafana instance will be created"
  type        = string
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "The resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "The Azure region where the Grafana instance will be created"
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

# Optional variables with defaults
variable "prometheus_workspace_id" {
  description = "The resource ID of the Azure Monitor workspace to integrate with Grafana"
  type        = string
  default     = null
}

variable "api_key_enabled" {
  description = "Whether to enable API key authentication for the Grafana instance"
  type        = bool
  default     = true
}

variable "deterministic_outbound_ip_enabled" {
  description = "Whether to enable deterministic outbound IPs for the Grafana instance"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether to enable public network access for the Grafana instance"
  type        = bool
  default     = true
}

variable "zone_redundancy_enabled" {
  description = "Whether to enable zone redundancy for the Grafana instance"
  type        = bool
  default     = true
}

variable "grafana_major_version" {
  description = "The major version of Grafana to use"
  type        = string
  default     = "10"
  
  validation {
    condition     = contains(["10", "11"], var.grafana_major_version)
    error_message = "The Grafana major version must be either 10 or 11."
  }
}

variable "auto_generated_domain_name_label_scope" {
  description = "The scope for the auto-generated domain name label"
  type        = string
  default     = "TenantReuse"
  
  validation {
    condition     = contains(["TenantReuse", "ResourceGroupReuse", "SubscriptionReuse", "None"], var.auto_generated_domain_name_label_scope)
    error_message = "The auto_generated_domain_name_label_scope must be one of: TenantReuse, ResourceGroupReuse, SubscriptionReuse, or None."
  }
}

variable "admin_group_object_ids" {
  description = "List of Microsoft Entra group Object IDs that will have the Grafana Admin role"
  type        = list(string)
  default     = []
}

variable "admin_user_object_ids" {
  description = "List of Microsoft Entra user Object IDs that will have the Grafana Admin role"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A mapping of tags to assign to the resource"
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