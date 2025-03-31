variable "name" {
  description = "The name of the Front Door profile"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,78}[a-zA-Z0-9]$", var.name))
    error_message = "The name must be between 3 and 80 characters long, can contain alphanumerics and hyphens, must start and end with alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group in which to create the Front Door profile"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_().]{1,90}$", var.resource_group_name))
    error_message = "Resource group names must be between 1 and 90 characters and can only include alphanumeric, underscore, parentheses, hyphen, and period."
  }
}

variable "sku_name" {
  description = "The SKU name of the Front Door profile (Standard_AzureFrontDoor or Premium_AzureFrontDoor)"
  type        = string
  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku_name)
    error_message = "Valid values for sku_name are Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "response_timeout_seconds" {
  description = "Response timeout in seconds. Possible values are between 16 and 240 seconds (inclusive)"
  type        = number
  default     = null
  validation {
    condition     = var.response_timeout_seconds == null || (var.response_timeout_seconds >= 16 && var.response_timeout_seconds <= 240)
    error_message = "Response timeout must be between 16 and 240 seconds (inclusive) or null."
  }
}

variable "tags" {
  description = "A mapping of tags to assign to the resource"
  type        = map(string)
  default     = {}
} 