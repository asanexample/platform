variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy the key vault in"
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
  description = "Azure region where the key vault will be deployed"
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

variable "name" {
  description = "Name of the key vault (if custom naming is required). If not provided, it will be auto-generated based on naming components."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || (length(var.name) >= 3 && length(var.name) <= 24)
    error_message = "Key vault name must be between 3 and 24 characters when provided."
  }

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9-]+$", var.name))
    error_message = "Key vault name can only include alphanumeric characters and hyphens."
  }
}

variable "name_components" {
  description = "Components to auto-generate the key vault name if 'name' is not provided"
  type = object({
    workload    = optional(string, "platform")
    environment = optional(string, "dev")
    region_abbv = optional(string, "eus")
    instance    = optional(string, "001")
  })
  default = {}
}

variable "sku_name" {
  description = "SKU name for the key vault (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], lower(var.sku_name))
    error_message = "SKU name must be either 'standard' or 'premium'."
  }
}

variable "enable_rbac_authorization" {
  description = "Whether to enable RBAC authorization for the key vault"
  type        = bool
  default     = true
}

variable "enabled_for_disk_encryption" {
  description = "Whether the key vault is enabled for disk encryption"
  type        = bool
  default     = false
}

variable "purge_protection_enabled" {
  description = "Whether purge protection is enabled for the key vault"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days for soft delete retention (7-90 days)"
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled for the key vault"
  type        = bool
  default     = false
}

variable "network_acls" {
  description = "Network ACLs for the key vault"
  type = object({
    bypass                     = optional(string, "AzureServices")
    default_action             = optional(string, "Deny")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.network_acls == null ? true : contains(["None", "AzureServices"], lookup(var.network_acls, "bypass", "AzureServices"))
    error_message = "Bypass must be one of: None, AzureServices."
  }

  validation {
    condition     = var.network_acls == null ? true : contains(["Allow", "Deny"], lookup(var.network_acls, "default_action", "Deny"))
    error_message = "Default action must be either Allow or Deny."
  }
}

variable "access_policies" {
  description = "Map of access policies for the key vault (used only when RBAC authorization is disabled)"
  type = map(object({
    tenant_id               = optional(string)
    object_id               = string
    key_permissions         = optional(list(string), [])
    secret_permissions      = optional(list(string), [])
    certificate_permissions = optional(list(string), [])
    storage_permissions     = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, policy in var.access_policies : alltrue([
        for permission in policy.key_permissions : contains([
          "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore",
          "Decrypt", "Encrypt", "UnwrapKey", "WrapKey", "Verify", "Sign", "Purge", "Release", "Rotate"
        ], permission)
      ])
    ])
    error_message = "Key permissions must be valid Azure Key Vault key permissions."
  }

  validation {
    condition = alltrue([
      for name, policy in var.access_policies : alltrue([
        for permission in policy.secret_permissions : contains([
          "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
        ], permission)
      ])
    ])
    error_message = "Secret permissions must be valid Azure Key Vault secret permissions."
  }

  validation {
    condition = alltrue([
      for name, policy in var.access_policies : alltrue([
        for permission in policy.certificate_permissions : contains([
          "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore",
          "ManageContacts", "ManageIssuers", "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers", "Purge"
        ], permission)
      ])
    ])
    error_message = "Certificate permissions must be valid Azure Key Vault certificate permissions."
  }

  validation {
    condition = alltrue([
      for name, policy in var.access_policies : alltrue([
        for permission in policy.storage_permissions : contains([
          "Get", "List", "Update", "Set", "Delete", "Recover", "Backup", "Restore", "RegenerateKey",
          "GetSAS", "ListSAS", "SetSAS", "DeleteSAS", "Purge"
        ], permission)
      ])
    ])
    error_message = "Storage permissions must be valid Azure Key Vault storage permissions."
  }
}

variable "private_endpoint" {
  description = "Configuration for private endpoint if required"
  type = object({
    create               = optional(bool, false)
    name                 = optional(string, "")
    subnet_id            = optional(string, "")
    private_dns_zone_ids = optional(list(string), [])
  })
  default = {}

  validation {
    condition = var.private_endpoint.create == false || (
      var.private_endpoint.subnet_id != ""
    )
    error_message = "Subnet ID is required when private endpoint is enabled."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
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