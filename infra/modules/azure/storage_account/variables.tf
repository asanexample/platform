variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy the storage account in"
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
  description = "Azure region where resources will be deployed"
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
  description = "Name of the storage account (if custom naming is required). If not provided, it will be auto-generated based on prefix, environment, region and instance components."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || (length(var.name) >= 3 && length(var.name) <= 24)
    error_message = "Storage account name must be between 3 and 24 characters when provided."
  }

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9]+$", var.name))
    error_message = "Storage account name can only include lowercase letters and numbers, with no hyphens or special characters."
  }
}

variable "name_components" {
  description = "Components to auto-generate the storage account name if 'name' is not provided"
  type = object({
    workload    = optional(string, "platform")
    environment = optional(string, "dev")
    region_abbv = optional(string, "eus")
    instance    = optional(string, "001")
  })
  default = {}
}

variable "account_kind" {
  description = "Kind of storage account to create"
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["BlobStorage", "BlockBlobStorage", "FileStorage", "Storage", "StorageV2"], var.account_kind)
    error_message = "Account kind must be one of: BlobStorage, BlockBlobStorage, FileStorage, Storage, StorageV2."
  }
}

variable "account_tier" {
  description = "Tier of storage account to create"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be either Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "Account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "Access tier must be either Hot or Cool."
  }
}

variable "min_tls_version" {
  description = "Minimum TLS version required by the storage account"
  type        = string
  default     = "TLS1_2"

  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

variable "allow_nested_items_to_be_public" {
  description = "Whether nested items (blobs, containers) can be set to public access"
  type        = bool
  default     = false
}

variable "shared_access_key_enabled" {
  description = "Whether shared access key authentication is enabled (not recommended, Entra ID authentication is preferred)"
  type        = bool
  default     = false
}

variable "blob_public_access_enabled" {
  description = "Whether public access is allowed to containers and blobs"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled for the storage account (independent of private endpoint configuration)"
  type        = bool
  default     = true
}

variable "network_rules" {
  description = "Network rules for the storage account"
  type = object({
    default_action             = optional(string, "Allow")
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules.default_action)
    error_message = "Default action must be either Allow or Deny."
  }

  validation {
    condition = alltrue([
      for bypass in var.network_rules.bypass : contains(["AzureServices", "Logging", "Metrics", "None"], bypass)
    ])
    error_message = "Bypass values must be one or more of: AzureServices, Logging, Metrics, None."
  }
}

variable "containers" {
  description = "List of containers to create in the storage account"
  type = map(object({
    name                  = string
    container_access_type = optional(string, "private")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.containers : can(regex("^[a-z0-9][-a-z0-9]{1,61}[a-z0-9]$", v.name))
    ])
    error_message = "Container names must be 3-63 characters long, start and end with a letter or number, and can contain only lowercase letters, numbers, and dashes."
  }

  validation {
    condition = alltrue([
      for k, v in var.containers : contains(["blob", "container", "private"], v.container_access_type)
    ])
    error_message = "Container access type must be one of: blob, container, private."
  }
}

variable "create_containers" {
  description = "Whether to create containers as part of this module. Set to false if you want to manage containers separately."
  type        = bool
  default     = true
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

  validation {
    condition = var.private_endpoint.create == false || (
      var.private_endpoint.subnet_id != ""
    )
    error_message = "Subnet ID is required when private endpoint is enabled."
  }

  validation {
    condition = alltrue([
      for subresource in var.private_endpoint.subresource_names : contains([
        "blob", "queue", "table", "file", "web", "dfs"
      ], subresource)
    ])
    error_message = "Subresource names must be one or more of: blob, queue, table, file, web, dfs."
  }
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

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules : length(rule.name) >= 3 && length(rule.name) <= 63
    ])
    error_message = "Lifecycle rule names must be between 3 and 63 characters."
  }
}

variable "blob_versioning_enabled" {
  description = "Whether blob versioning is enabled"
  type        = bool
  default     = false
}

variable "last_access_time_enabled" {
  description = "Whether last access time tracking is enabled"
  type        = bool
  default     = false
}

variable "change_feed_enabled" {
  description = "Whether the change feed is enabled"
  type        = bool
  default     = false
}

variable "container_delete_retention_days" {
  description = "Number of days to retain deleted containers. If specified, must be between 1 and 365."
  type        = number
  default     = null

  validation {
    condition     = var.container_delete_retention_days == null ? true : (var.container_delete_retention_days >= 1 && var.container_delete_retention_days <= 365)
    error_message = "Container delete retention days must be between 1 and 365."
  }
}

variable "blob_delete_retention_days" {
  description = "Number of days to retain deleted blobs. If specified, must be between 1 and 365."
  type        = number
  default     = null

  validation {
    condition     = var.blob_delete_retention_days == null ? true : (var.blob_delete_retention_days >= 1 && var.blob_delete_retention_days <= 365)
    error_message = "Blob delete retention days must be between 1 and 365."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "role_assignments" {
  description = "List of role assignments to create for Entra ID authentication. Should contain principal_id, role_definition_name or role_definition_id, and scope (optional)."
  type = list(object({
    principal_id         = string
    role_definition_name = optional(string, null)
    role_definition_id   = optional(string, null)
    description          = optional(string, null)
    scope                = optional(string, null) # Defaults to storage account resource ID
  }))
  default = []

  validation {
    condition = alltrue([
      for ra in var.role_assignments : ra.role_definition_name != null || ra.role_definition_id != null
    ])
    error_message = "Either role_definition_name or role_definition_id must be provided for each role assignment."
  }
}

/**
 * CORS (Cross-Origin Resource Sharing) configuration for the storage account.
 * This allows you to specify which origins, HTTP methods, and headers are allowed
 * when making requests to this storage account from web browsers.
 */
variable "cors_rules" {
  description = "CORS rules for the storage account blob service"
  type = list(object({
    allowed_origins    = list(string) # List of origin domains that are permitted to make requests
    allowed_methods    = list(string) # HTTP methods that are allowed (GET, PUT, POST, DELETE, HEAD, OPTIONS)
    allowed_headers    = list(string) # HTTP request headers that are supported
    exposed_headers    = list(string) # Response headers that browsers are allowed to access
    max_age_in_seconds = number       # How long browsers should cache CORS preflight response
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.cors_rules : alltrue([
        for method in rule.allowed_methods : contains(["DELETE", "GET", "HEAD", "MERGE", "OPTIONS", "PATCH", "POST", "PUT"], method)
      ])
    ])
    error_message = "Allowed methods must be one or more of: DELETE, GET, HEAD, MERGE, OPTIONS, PATCH, POST, PUT."
  }

  validation {
    condition = alltrue([
      for rule in var.cors_rules : length(rule.allowed_origins) > 0 && length(rule.allowed_methods) > 0
    ])
    error_message = "At least one allowed origin and one allowed method must be specified per CORS rule."
  }

  validation {
    condition = alltrue([
      for rule in var.cors_rules : rule.max_age_in_seconds >= 0 && rule.max_age_in_seconds <= 2000000000
    ])
    error_message = "Max age in seconds must be between 0 and 2,000,000,000."
  }
}

/**
 * Customer-managed key configuration for storage account encryption.
 * By default, Azure uses Microsoft-managed keys. This allows you to use your own keys
 * stored in Azure Key Vault for enhanced control over encryption.
 */
variable "customer_managed_key" {
  description = "Customer-managed key configuration for storage account encryption"
  type = object({
    key_vault_key_id             = string                 # ID of the key vault key used for encryption
    user_assigned_identity_id    = optional(string, null) # ID of user-assigned managed identity with key access
    use_system_assigned_identity = optional(bool, false)  # Whether to use system-assigned identity instead

    # Optional key auto-rotation settings
    key_rotation = optional(object({
      auto_rotation_enabled  = optional(bool, false) # Whether key auto-rotation is enabled
      rotation_interval_days = optional(number, 90)  # Number of days before auto-rotating the key
    }), {})
  })
  default = null

  validation {
    condition = var.customer_managed_key == null ? true : (
      (var.customer_managed_key.user_assigned_identity_id != null && !var.customer_managed_key.use_system_assigned_identity) ||
      (var.customer_managed_key.user_assigned_identity_id == null && var.customer_managed_key.use_system_assigned_identity)
    )
    error_message = "Either user_assigned_identity_id must be provided or use_system_assigned_identity must be true, but not both."
  }

  validation {
    condition = var.customer_managed_key == null ? true : (
      var.customer_managed_key.key_rotation.rotation_interval_days >= 7 &&
      var.customer_managed_key.key_rotation.rotation_interval_days <= 365
    )
    error_message = "Key rotation interval days must be between 7 and 365 days."
  }
} 