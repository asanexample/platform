variable "resource_group_name" {
  description = "The name of the resource group in which to create the private DNS zones"
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

variable "private_dns_zones" {
  description = "Map of private DNS zones to create"
  type = map(object({
    name                      = string
    vnet_id                   = string
    vnet_resource_group_name  = string
    registration_enabled      = bool
    virtual_network_link_name = string
  }))

  validation {
    condition = alltrue([
      for k, v in var.private_dns_zones : length(v.name) >= 1 && length(v.name) <= 253
    ])
    error_message = "DNS zone names must be between 1 and 253 characters."
  }

  validation {
    condition = alltrue([
      for k, v in var.private_dns_zones : can(regex("^[a-z0-9][a-z0-9-]*(\\.[a-z0-9][a-z0-9-]*)*$", v.name))
    ])
    error_message = "DNS zone names must be valid domain names: use lowercase letters, numbers, hyphens, and periods. Segments must start and end with a letter or number."
  }
}

variable "tags" {
  description = "A mapping of tags to assign to the resources"
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