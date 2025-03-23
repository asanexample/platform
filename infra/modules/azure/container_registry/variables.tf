/**
 * Variables for the Azure Container Registry Module
 * 
 * This file defines all input variables for the ACR module
 */

# Creation control
variable "create_registry" {
  description = "Whether to create an Azure Container Registry. If false, all other resources will not be created."
  type        = bool
  default     = true
}

# Basic resource information
variable "name" {
  description = "Name of the ACR resource. If not provided, a name will be generated using prefix, environment, and region."
  type        = string
  default     = null
  
  validation {
    condition     = var.name == null ? true : can(regex("^[a-zA-Z0-9]+$", var.name)) && length(var.name) >= 5 && length(var.name) <= 50
    error_message = "ACR name must be between 5 and 50 characters, containing only alphanumeric characters."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group in which to create the ACR."
  type        = string
}

variable "location" {
  description = "The Azure region where the ACR should be created."
  type        = string
}

# Naming convention variables
variable "prefix" {
  description = "A prefix for resources, used in naming convention."
  type        = string
  default     = "vip"
}

variable "environment" {
  description = "The environment (e.g., dev, preprod, prod) for naming and tagging."
  type        = string
  
  validation {
    condition     = contains(["dev", "preprod", "prod", "test", "stg"], var.environment)
    error_message = "Environment must be one of: dev, preprod, prod, test, stg."
  }
}

variable "region_abbv" {
  description = "Abbreviated Azure region name for use in resource naming."
  type        = string
  
  validation {
    condition     = length(var.region_abbv) <= 5
    error_message = "Region abbreviation should not be longer than 5 characters."
  }
}

# ACR configurations
variable "sku" {
  description = "The SKU of the Azure Container Registry (Basic, Standard, or Premium)."
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "ACR SKU must be one of: Basic, Standard, Premium."
  }
}

variable "admin_enabled" {
  description = "Whether admin access is enabled. Not recommended for production."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled."
  type        = bool
  default     = true
}

# Premium SKU features
variable "zone_redundancy_enabled" {
  description = "Whether zone redundancy is enabled (Premium SKU only)."
  type        = bool
  default     = false
}

variable "data_endpoint_enabled" {
  description = "Whether a data endpoint is enabled (Premium SKU only)."
  type        = bool
  default     = false
}

variable "geo_replication_locations" {
  description = "List of Azure locations where the container registry should be geo-replicated (Premium SKU only)."
  type = list(object({
    location                = string
    zone_redundancy_enabled = optional(bool, false)
    tags                    = optional(map(string), {})
  }))
  default = []
}

# Network configuration
variable "network_rule_set" {
  description = "Network rules for the ACR (Standard and Premium SKUs only). Contains IP allow rules."
  type = object({
    default_action  = string
    ip_rules        = list(string)
  })
  default = null
}

# Encryption settings
variable "encryption_enabled" {
  description = "Whether encryption is enabled (Premium SKU only)."
  type        = bool
  default     = false
}

variable "key_vault_key_id" {
  description = "The ID of the Key Vault key to use for encryption (Premium SKU only)."
  type        = string
  default     = null
}

variable "encryption_identity_id" {
  description = "The ID of the user assigned identity to use for encryption (Premium SKU only)."
  type        = string
  default     = null
}

# Security and retention settings
variable "lock_resource" {
  description = "Whether to add a CanNotDelete lock to the registry."
  type        = bool
  default     = false
}

variable "retention_policy_days" {
  description = "The number of days to retain images. 0 means no retention policy."
  type        = number
  default     = 0
  
  validation {
    condition     = var.retention_policy_days >= 0 && var.retention_policy_days <= 365
    error_message = "Retention policy days must be between 0 and 365."
  }
}

# AKS integration
variable "aks_integration_enabled" {
  description = "Whether to enable integration with AKS."
  type        = bool
  default     = false
}

variable "aks_principal_id" {
  description = "The principal ID of the AKS cluster identity for role assignments."
  type        = string
  default     = null
}

variable "enable_aks_acr_push" {
  description = "Whether to enable pushing images from AKS to ACR."
  type        = bool
  default     = false
}

# Tagging
variable "tags" {
  description = "A map of tags to assign to the ACR."
  type        = map(string)
  default     = {}
} 