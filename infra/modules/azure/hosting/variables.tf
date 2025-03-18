/**
 * # Shared Infrastructure Variables
 * 
 * Variables for deploying both networking and storage in a single resource group.
 */

# Shared variables
variable "resource_group_name" {
  description = "Name of the resource group to deploy resources in"
  type        = string
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

# Network variables
variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
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

# Storage variables
variable "storage_name_components" {
  description = "Components to auto-generate the storage account name"
  type = object({
    prefix      = optional(string, "app")
    environment = optional(string, "dev")
    region_abbv = optional(string, "eus")
    instance    = optional(string, "001")
  })
  default = {}
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

variable "networking_module_source" {
  description = "Source path for the networking module"
  type        = string
  default     = "../networking"
}

variable "storage_module_source" {
  description = "Source path for the storage module"
  type        = string
  default     = "../storage"
} 