variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "name" {
  description = "Base name used to derive resource names (resource group, VNet, key vault)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod, ops)"
  type        = string
}

variable "workload" {
  description = "Workload identifier for resource names"
  type        = string
}

variable "region_abbv" {
  description = "Abbreviated region code for resource naming"
  type        = string
}

variable "address_space" {
  description = "VNet address space CIDR blocks"
  type        = list(string)
}

variable "subnets" {
  description = "Subnet definitions (same schema as the networking module)"
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
    delegation        = optional(map(list(map(string))), {})
  }))
  default = {}
}

variable "enable_aks_networking" {
  description = "Whether to configure AKS-specific networking (NSG rules, private DNS)"
  type        = bool
  default     = false
}

variable "aks_cluster_name" {
  description = "AKS cluster name (required if enable_aks_networking is true)"
  type        = string
  default     = null
}

variable "aks_subnet_name" {
  description = "Subnet name for AKS nodes"
  type        = string
  default     = null
}

variable "enable_key_vault" {
  description = "Whether to create a Key Vault as part of the base stack"
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "Key Vault SKU (standard or premium)"
  type        = string
  default     = "standard"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
