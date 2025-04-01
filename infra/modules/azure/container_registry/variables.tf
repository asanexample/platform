/**
 * Variables for the Azure Container Registry Module
 * 
 * This file defines all input variables for the ACR module
 */

# Creation control
variable "create_registry" {
  description = "Whether to create the Azure Container Registry"
  type        = bool
  default     = true

  validation {
    condition     = var.create_registry != null
    error_message = "The create_registry variable must be specified as either true or false."
  }
}

# Basic resource information
variable "name" {
  description = "The name of the Azure Container Registry. If null, will use prefix, environment, and region_abbv to create a name"
  type        = string
  default     = null

  validation {
    condition     = var.name == null || (length(var.name) >= 5 && length(var.name) <= 50 && can(regex("^[a-zA-Z0-9]*$", var.name)))
    error_message = "ACR name must be 5-50 characters long and contain only alphanumeric characters."
  }
}

variable "resource_group_name" {
  description = "The resource group name for the ACR"
  type        = string

  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 63 && can(regex("^[a-zA-Z0-9-_\\(\\)\\.]+$", var.resource_group_name))
    error_message = "Resource group name must be 3-63 characters and can include alphanumeric, hyphen, underscore, parentheses, and period."
  }
}

variable "location" {
  description = "The location for the ACR"
  type        = string

  validation {
    condition     = contains(["eastus", "eastus2", "southcentralus", "westus", "westus2", "westus3", "centralus", "northcentralus", "brazilsouth", "eastasia", "southeastasia", "northeurope", "westeurope", "centralindia", "southindia", "japaneast", "japanwest", "koreacentral", "southafricanorth", "australiaeast", "australiasoutheast", "canadacentral", "canadaeast", "germanywestcentral", "norwayeast", "swedencentral", "switzerlandnorth", "uaenorth", "uksouth", "ukwest", "francecentral", "jioindiawest", "westcentralus"], var.location)
    error_message = "The location must be a valid Azure region name."
  }
}

# Naming convention variables
variable "prefix" {
  description = "The prefix to use for resource names"
  type        = string

  validation {
    condition     = length(var.prefix) >= 1 && length(var.prefix) <= 10 && can(regex("^[a-zA-Z0-9-_]+$", var.prefix))
    error_message = "The prefix must be 1-10 characters and can include alphanumeric, hyphen, and underscore characters."
  }
}

variable "environment" {
  description = "The environment for the resources"
  type        = string

  validation {
    condition     = contains(["dev", "preprod", "prod", "test", "stg", "ops"], var.environment)
    error_message = "The environment must be one of: dev, preprod, prod, test, stg, ops."
  }
}

variable "region_abbv" {
  description = "The abbreviation for the Azure region"
  type        = string

  validation {
    condition     = length(var.region_abbv) >= 2 && length(var.region_abbv) <= 5 && can(regex("^[a-z]+$", var.region_abbv))
    error_message = "The region abbreviation must be 2-5 lowercase letters."
  }
}

# ACR configurations
variable "sku" {
  description = "The SKU of the ACR (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "The SKU must be one of: Basic, Standard, Premium."
  }
}

variable "admin_enabled" {
  description = "Whether to enable the admin user for the ACR"
  type        = bool
  default     = false

  validation {
    condition     = var.admin_enabled != null
    error_message = "The admin_enabled variable must be specified as either true or false."
  }
}

variable "public_network_access_enabled" {
  description = "Whether to enable public network access for the ACR"
  type        = bool
  default     = true

  validation {
    condition     = var.public_network_access_enabled != null
    error_message = "The public_network_access_enabled variable must be specified as either true or false."
  }
}

# Premium SKU features
variable "zone_redundancy_enabled" {
  description = "Whether to enable zone redundancy for the ACR (Premium SKU only)"
  type        = bool
  default     = false

  validation {
    condition     = var.zone_redundancy_enabled != null
    error_message = "The zone_redundancy_enabled variable must be specified as either true or false."
  }
}

variable "data_endpoint_enabled" {
  description = "Whether to enable the data endpoint for the ACR (Premium SKU only)"
  type        = bool
  default     = false

  validation {
    condition     = var.data_endpoint_enabled != null
    error_message = "The data_endpoint_enabled variable must be specified as either true or false."
  }
}

variable "geo_replication_locations" {
  description = "The list of locations for geo-replication of the ACR (Premium SKU only)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for location in var.geo_replication_locations :
      contains(["eastus", "eastus2", "southcentralus", "westus", "westus2", "westus3", "centralus", "northcentralus", "brazilsouth", "eastasia", "southeastasia", "northeurope", "westeurope", "centralindia", "southindia", "japaneast", "japanwest", "koreacentral", "southafricanorth", "australiaeast", "australiasoutheast", "canadacentral", "canadaeast", "germanywestcentral", "norwayeast", "swedencentral", "switzerlandnorth", "uaenorth", "uksouth", "ukwest", "francecentral", "jioindiawest", "westcentralus"], location)
    ])
    error_message = "All geo-replication locations must be valid Azure region names."
  }
}

# Network configuration
variable "network_rule_set" {
  description = "The network rule set for the ACR (Premium SKU only)"
  type = object({
    default_action = string
    ip_rules = list(object({
      action   = string
      ip_range = string
    }))
  })
  default = {
    default_action = "Allow"
    ip_rules       = []
  }

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rule_set.default_action)
    error_message = "The network_rule_set.default_action must be one of: Allow, Deny."
  }

  validation {
    condition = alltrue([
      for rule in var.network_rule_set.ip_rules :
      contains(["Allow"], rule.action) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(\\/([0-9]|[1-2][0-9]|3[0-2]))?$", rule.ip_range))
    ])
    error_message = "Each IP rule action must be 'Allow' and the IP range must be a valid CIDR notation."
  }
}

# Encryption settings
variable "encryption_enabled" {
  description = "Whether to enable encryption for the ACR (Premium SKU only)"
  type        = bool
  default     = false

  validation {
    condition     = var.encryption_enabled != null
    error_message = "The encryption_enabled variable must be specified as either true or false."
  }
}

variable "key_vault_key_id" {
  description = "The ID of the Key Vault key to use for encryption (Premium SKU only, required if encryption_enabled is true)"
  type        = string
  default     = null

  validation {
    condition     = var.key_vault_key_id == null ? true : (length(coalesce(var.key_vault_key_id, "")) > 10 && can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+/keys/[^/]+(/versions/[^/]+)?$", var.key_vault_key_id)))
    error_message = "The key_vault_key_id must be a valid Azure Key Vault key resource ID."
  }
}

variable "encryption_identity_id" {
  description = "The ID of the user-assigned identity to use for encryption (Premium SKU only, required if encryption_enabled is true)"
  type        = string
  default     = null

  validation {
    condition     = var.encryption_identity_id == null ? true : (length(coalesce(var.encryption_identity_id, "")) > 10 && can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ManagedIdentity/userAssignedIdentities/[^/]+$", var.encryption_identity_id)))
    error_message = "The encryption_identity_id must be a valid user-assigned managed identity resource ID."
  }
}

# Security and retention settings
variable "lock_resource" {
  description = "Whether to lock the resource to prevent accidental deletion"
  type        = bool
  default     = false

  validation {
    condition     = var.lock_resource != null
    error_message = "The lock_resource variable must be specified as either true or false."
  }
}

variable "retention_policy_days" {
  description = "The number of days to retain images for in the ACR (Premium SKU only, 0 to disable)"
  type        = number
  default     = 0

  validation {
    condition     = var.retention_policy_days >= 0 && var.retention_policy_days <= 365
    error_message = "The retention_policy_days must be between 0 and 365."
  }
}

# AKS integration
variable "aks_integration_enabled" {
  description = "Whether to enable AKS integration for the ACR"
  type        = bool
  default     = false

  validation {
    condition     = var.aks_integration_enabled != null
    error_message = "The aks_integration_enabled variable must be specified as either true or false."
  }
}

variable "aks_principal_id" {
  description = "The principal ID of the AKS cluster to integrate with the ACR (required if aks_integration_enabled is true)"
  type        = string
  default     = null

  validation {
    condition     = var.aks_principal_id == null || can(regex("^[a-zA-Z0-9-]+$", var.aks_principal_id))
    error_message = "The aks_principal_id must be a valid principal ID format."
  }
}

variable "enable_aks_acr_push" {
  description = "Whether to enable AKS to push images to the ACR (if aks_integration_enabled is true)"
  type        = bool
  default     = false

  validation {
    condition     = var.enable_aks_acr_push != null
    error_message = "The enable_aks_acr_push variable must be specified as either true or false."
  }
}

# Tagging
variable "tags" {
  description = "The tags to assign to the resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.tags : length(k) >= 1 && length(k) <= 512 && length(v) <= 256
    ])
    error_message = "Tag keys must be between 1 and 512 characters, tag values must be 256 characters or less."
  }
} 