variable "create" {
  description = "Controls whether the Front Door Private Link module is deployed"
  type        = bool
  default     = true
}

variable "origin_group_id" {
  description = "The ID of the Front Door origin group. If provided, origin_group_name, profile_name, and profile_resource_group_name are not required."
  type        = string
  default     = null
}

variable "origin_group_name" {
  description = "The name of the Front Door origin group. Required if origin_group_id is not provided."
  type        = string
  default     = null
  validation {
    condition     = var.origin_group_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,78}[a-zA-Z0-9]$", var.origin_group_name))
    error_message = "If provided, origin group name must be between 3 and 80 characters long, can contain alphanumerics and hyphens, must start and end with alphanumeric."
  }
}

variable "profile_name" {
  description = "The name of the Front Door profile. Required if origin_group_id is not provided."
  type        = string
  default     = null
  validation {
    condition     = var.profile_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,78}[a-zA-Z0-9]$", var.profile_name))
    error_message = "If provided, profile name must be between 3 and 80 characters long, can contain alphanumerics and hyphens, must start and end with alphanumeric."
  }
}

variable "profile_resource_group_name" {
  description = "The name of the resource group containing the Front Door profile. Required if origin_group_id is not provided."
  type        = string
  default     = null
  validation {
    condition     = var.profile_resource_group_name == null || can(regex("^[a-zA-Z0-9-_().]{1,90}$", var.profile_resource_group_name))
    error_message = "If provided, resource group names must be between 1 and 90 characters and can only include alphanumeric, underscore, parentheses, hyphen, and period."
  }
}

variable "storage_account_name" {
  description = "The name of the storage account"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be between 3 and 24 characters, and may contain only lowercase letters and numbers."
  }
}

variable "storage_resource_group_name" {
  description = "The name of the resource group containing the storage account"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_().]{1,90}$", var.storage_resource_group_name))
    error_message = "Resource group names must be between 1 and 90 characters and can only include alphanumeric, underscore, parentheses, hyphen, and period."
  }
}

variable "origin_name" {
  description = "The name of the origin"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,78}[a-zA-Z0-9]$", var.origin_name))
    error_message = "Origin name must be between 3 and 80 characters long, can contain alphanumerics and hyphens, must start and end with alphanumeric."
  }
}

variable "enabled" {
  description = "Whether the origin is enabled"
  type        = bool
  default     = true
}

variable "certificate_name_check_enabled" {
  description = "Whether to enable certificate name check"
  type        = bool
  default     = true
}

variable "use_blob_endpoint" {
  description = "Whether to use the blob endpoint instead of the web endpoint"
  type        = bool
  default     = true
}

variable "priority" {
  description = "Priority of origin in given origin group"
  type        = number
  default     = 1
  validation {
    condition     = var.priority >= 1 && var.priority <= 5
    error_message = "Priority must be between 1 and 5 inclusive."
  }
}

variable "weight" {
  description = "Weight of origin in given origin group"
  type        = number
  default     = 500
  validation {
    condition     = var.weight >= 1 && var.weight <= 1000
    error_message = "Weight must be between 1 and 1000 inclusive."
  }
}

variable "private_link_request_message" {
  description = "The message to include in the request for private link approval"
  type        = string
  default     = "Request access for Private Link Origin CDN Frontdoor"
}

# Route variables
variable "route_enabled" {
  description = "Whether to create a route for this origin"
  type        = bool
  default     = true
}

variable "endpoint_id" {
  description = "The ID of the Front Door endpoint. Required if route_enabled is true."
  type        = string
  default     = null
}

variable "route_name" {
  description = "The name of the route. Required if route_enabled is true."
  type        = string
  default     = null
  validation {
    condition     = var.route_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,78}[a-zA-Z0-9]$", var.route_name))
    error_message = "If provided, route name must be between 3 and 80 characters long, can contain alphanumerics and hyphens, must start and end with alphanumeric."
  }
}

variable "forwarding_protocol" {
  description = "Protocol to use when forwarding traffic"
  type        = string
  default     = "HttpsOnly"
  validation {
    condition     = contains(["HttpOnly", "HttpsOnly", "MatchRequest"], var.forwarding_protocol)
    error_message = "Forwarding protocol must be one of HttpOnly, HttpsOnly, or MatchRequest."
  }
}

variable "https_redirect_enabled" {
  description = "Whether to enable HTTPS redirect"
  type        = bool
  default     = true
}

variable "patterns_to_match" {
  description = "The route patterns to match"
  type        = list(string)
  default     = ["/*"]
  validation {
    condition     = length(var.patterns_to_match) > 0
    error_message = "At least one pattern must be specified."
  }
}

variable "supported_protocols" {
  description = "Supported protocols for this route"
  type        = list(string)
  default     = ["Http", "Https"]
  validation {
    condition     = length(var.supported_protocols) > 0
    error_message = "At least one protocol must be specified."
  }
  validation {
    condition     = length([for p in var.supported_protocols : p if !contains(["Http", "Https"], p)]) == 0
    error_message = "Supported protocols must be either Http or Https."
  }
}

variable "link_to_default_domain" {
  description = "Whether to link to the default domain"
  type        = bool
  default     = true
}

variable "cache_enabled" {
  description = "Whether to enable caching for this route"
  type        = bool
  default     = true
}

variable "cache_settings" {
  description = "Cache settings for the route"
  type = object({
    query_string_caching_behavior = optional(string, "UseQueryString")
    query_strings                 = optional(list(string))
    compression_enabled           = optional(bool, false)
    content_types_to_compress     = optional(list(string))
  })
  default = {
    query_string_caching_behavior = "UseQueryString"
    compression_enabled           = false
  }
  validation {
    condition     = contains(["IgnoreQueryString", "UseQueryString", "IncludeSpecifiedQueryStrings", "ExcludeSpecifiedQueryStrings"], var.cache_settings.query_string_caching_behavior)
    error_message = "Query string caching behavior must be one of IgnoreQueryString, UseQueryString, IncludeSpecifiedQueryStrings, or ExcludeSpecifiedQueryStrings."
  }
}

variable "storage_primary_blob_host" {
  description = "The primary blob host of the storage account (e.g., storageaccount.blob.core.windows.net)"
  type        = string
}

variable "storage_primary_web_host" {
  description = "The primary web host of the storage account (e.g., storageaccount.web.core.windows.net)"
  type        = string
}

variable "storage_location" {
  description = "The Azure region where the storage account is located"
  type        = string
}

variable "storage_account_id" {
  description = "The resource ID of the storage account"
  type        = string
} 