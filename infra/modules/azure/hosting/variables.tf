/**
 * # Shared Infrastructure Variables
 * 
 * Variables for deploying networking, storage, and key vault in a single resource group.
 */

# Naming variables
variable "prefix" {
  description = "Prefix to use for resource naming (usually 'vip')"
  type        = string
  default     = "vip"
}

variable "customer" {
  description = "Customer name to use in resource naming (optional for shared resources)"
  type        = string
  default     = null
}

variable "stage" {
  description = "Environment stage (dev, test, prod, etc.)"
  type        = string
}

variable "region_abbv" {
  description = "Abbreviated Azure region name (e.g., eus, wus, etc.)"
  type        = string
}

# Resource group variables - Deprecated, maintained for backward compatibility
variable "resource_group_name" {
  description = "DEPRECATED: Name of the resource group is now derived from the naming module"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Network variables - Deprecated, maintained for backward compatibility
variable "vnet_name" {
  description = "DEPRECATED: Name of the virtual network is now derived from the naming module"
  type        = string
  default     = null
}

variable "address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnet configurations"
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
    delegation        = optional(map(list(map(string))), {})
  }))
}

variable "dns_servers" {
  description = "List of DNS servers to use with the virtual network"
  type        = list(string)
  default     = []
}

# Storage variables - Deprecated, maintained for backward compatibility
variable "storage_name_components" {
  description = "DEPRECATED: Storage account name is now derived from the naming module"
  type = object({
    prefix      = optional(string, "app")
    environment = optional(string, "dev")
    region_abbv = optional(string, "eus")
    instance    = optional(string, "001")
  })
  default = {}
}

variable "storage_account_name" {
  description = "DEPRECATED: Storage account name is now derived from the naming module"
  type        = string
  default     = null
}

variable "storage_account_tier" {
  description = "Tier of storage account to create"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
}

variable "storage_network_default_action" {
  description = "Default action for storage network rules"
  type        = string
  default     = "Deny"
}

variable "storage_network_bypass" {
  description = "List of services to bypass storage network rules"
  type        = list(string)
  default     = ["AzureServices"]
}

variable "storage_allowed_subnets" {
  description = "List of subnet names from the network module that can access storage"
  type        = list(string)
  default     = []
}

variable "storage_containers" {
  description = "Map of containers to create in the storage account"
  type = map(object({
    name                  = string
    container_access_type = optional(string, "private")
  }))
  default = {}
}

variable "storage_allow_public" {
  description = "Whether to allow public access to storage containers"
  type        = bool
  default     = false
}

variable "storage_cors_rules" {
  description = "CORS rules for the storage account blob service"
  type = list(object({
    allowed_origins    = list(string)
    allowed_methods    = list(string)
    allowed_headers    = list(string)
    exposed_headers    = list(string)
    max_age_in_seconds = number
  }))
  default = []
}

# Key Vault variables
variable "create_key_vault" {
  description = "Whether to create a key vault as part of the hosting infrastructure"
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "The SKU name of the key vault (standard or premium)"
  type        = string
  default     = "standard"
}

variable "key_vault_enable_rbac" {
  description = "Whether to enable RBAC authorization for the key vault"
  type        = bool
  default     = true
}

variable "key_vault_enable_disk_encryption" {
  description = "Whether to enable the key vault for disk encryption"
  type        = bool
  default     = false
}

variable "key_vault_purge_protection" {
  description = "Whether to enable purge protection on the key vault"
  type        = bool
  default     = true
}

variable "key_vault_retention_days" {
  description = "Soft delete retention days for the key vault (7-90 days)"
  type        = number
  default     = 90
}

variable "key_vault_public_access" {
  description = "Whether to enable public network access to the key vault"
  type        = bool
  default     = false
}

variable "key_vault_allowed_subnets" {
  description = "List of subnet names that are allowed to access the key vault"
  type        = list(string)
  default     = null
}

variable "key_vault_access_policies" {
  description = "Map of access policies for the key vault (used only when RBAC is disabled)"
  type = map(object({
    tenant_id               = optional(string)
    object_id               = string
    key_permissions         = optional(list(string), [])
    secret_permissions      = optional(list(string), [])
    certificate_permissions = optional(list(string), [])
    storage_permissions     = optional(list(string), [])
  }))
  default = {}
}

variable "key_vault_private_endpoint_subnet" {
  description = "Subnet name for the key vault private endpoint (empty means no private endpoint)"
  type        = string
  default     = ""
}

variable "key_vault_private_dns_zone_ids" {
  description = "List of private DNS zone IDs for the key vault private endpoint"
  type        = list(string)
  default     = []
} 