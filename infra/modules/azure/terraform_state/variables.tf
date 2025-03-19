/**
 * Azure Terraform State Storage Module - Variables
 *
 * This module creates an Azure Storage Account optimized for Terraform state storage,
 * enforcing best practices like blob versioning, ZRS replication, and retention policies.
 * These variables control the configuration of the storage account and its features.
 */

variable "resource_group_name" {
  description = "Name of the resource group to deploy the storage account in"
  type        = string
  # Required: This resource group must exist before deploying the Terraform state storage
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  # Example: "eastus", "westus", "centralus", etc.
}

variable "storage_account_name" {
  description = "Name of the storage account (if custom naming is required)"
  type        = string
  default     = ""
  # Optional: If not provided, the name will be auto-generated from name_components
  # Must be globally unique, between 3-24 characters, lowercase letters and numbers only
}

variable "name_components" {
  description = "Components to auto-generate the storage account name if 'name' is not provided"
  type = object({
    prefix      = optional(string, "vip")
    environment = optional(string, "dev")
    region_abbv = optional(string, "eus")
    instance    = optional(string, "001")
  })
  default = {}
  # Used to generate a name following pattern: {prefix}{environment}{region_abbv}{instance}
  # Example: "vipdeveus001" for a development storage account in East US
}

variable "tfstate_container_name" {
  description = "Name of the container for Terraform state files"
  type        = string
  default     = "tfstate"
  # Default container name where Terraform state files will be stored
  # This container is always created by this module
}

variable "account_replication_type" {
  description = "Replication type for the storage account. Will default to ZRS if LRS is specified."
  type        = string
  default     = "ZRS"
  # ZRS (Zone-Redundant Storage) is the minimum recommended for Terraform state
  # Other options: GRS, RAGRS, GZRS, RAGZRS offer geo-redundancy for critical environments

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "Account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "blob_delete_retention_days" {
  description = "Number of days to retain deleted blobs. Defaults to 7 days."
  type        = number
  default     = 7
  # Important for recovery of accidentally deleted Terraform state files
  # For production environments, consider increasing to 30+ days

  validation {
    condition     = var.blob_delete_retention_days >= 1 && var.blob_delete_retention_days <= 365
    error_message = "Blob delete retention days must be between 1 and 365."
  }
}

variable "container_delete_retention_days" {
  description = "Number of days to retain deleted containers. Defaults to 7 days."
  type        = number
  default     = 7
  # Protection against accidental deletion of the entire state container
  # Consider aligning with blob_delete_retention_days for consistency

  validation {
    condition     = var.container_delete_retention_days >= 1 && var.container_delete_retention_days <= 365
    error_message = "Container delete retention days must be between 1 and 365."
  }
}

variable "additional_containers" {
  description = "Additional containers to create in the storage account"
  type = map(object({
    name                  = string
    container_access_type = optional(string, "private")
  }))
  default = {}
  # Optional additional containers beyond the default tfstate container
  # Useful for storing plan files, modules, or other Terraform-related artifacts
}

variable "network_rules" {
  description = "Network rules for the storage account"
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = {}
  # Security settings to restrict network access to the storage account
  # Default deny with AzureServices bypass allows Azure DevOps to still access state
}

variable "private_endpoint" {
  description = "Configuration for private endpoint if required"
  type = object({
    create               = optional(bool, false)
    name                 = optional(string, "")
    subnet_id            = optional(string, "")
    private_dns_zone_ids = optional(list(string), [])
    subresource_names    = optional(list(string), ["blob"])
  })
  default = {}
  # For maximum security, use private endpoints to access storage over private network
  # Requires an existing VNet/subnet and private DNS zone for privatelink.blob.core.windows.net
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for blob storage"
  type = list(object({
    name         = string
    enabled      = optional(bool, true)
    prefix_match = optional(list(string), [])

    delete_action = optional(object({
      days_after_modification_greater_than = number
    }), null)

    tier_to_cool_action = optional(object({
      days_after_modification_greater_than = number
    }), null)

    tier_to_archive_action = optional(object({
      days_after_modification_greater_than = number
    }), null)
  }))
  default = []
  # Optional lifecycle rules for managing older state files
  # Example: Archive state files older than 90 days, delete older than 365 days
}

variable "change_feed_enabled" {
  description = "Whether the change feed is enabled"
  type        = bool
  default     = false
  # Enables change feed for auditing changes to state files
  # Useful for compliance and tracking who/what modified state
}

variable "last_access_time_enabled" {
  description = "Whether last access time tracking is enabled"
  type        = bool
  default     = false
  # Enables tracking of last access time for lifecycle management
}

variable "blob_public_access_enabled" {
  description = "Whether public access is allowed to containers and blobs"
  type        = bool
  default     = false
  # Should always be false for Terraform state storage for security
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  # Recommended tags: Owner, Environment, Purpose, CostCenter
} 