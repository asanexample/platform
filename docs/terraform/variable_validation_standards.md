# Terraform Variable Validation Standards

This document outlines the standard validation patterns for variables in Terraform modules. These patterns should be followed consistently across all modules to ensure robust and predictable behavior.

## General Guidelines

1. **All variables should have a description**
2. **All variables should have a type declaration**
3. **Optional variables should have a default value**
4. **Critical variables should have appropriate validation**

## Common Variable Types and Validation Patterns

### Resource Group Name

```hcl
variable "resource_group_name" {
  description = "Name of the resource group"
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
```

### Azure Region/Location

```hcl
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
```

### Storage Account Name

```hcl
variable "name" {
  description = "Name of the storage account"
  type        = string
  default     = ""  # If using auto-generation logic

  validation {
    condition     = var.name == "" || (length(var.name) >= 3 && length(var.name) <= 24)
    error_message = "Storage account name must be between 3 and 24 characters when provided."
  }

  validation {
    condition     = var.name == "" || can(regex("^[a-z0-9]+$", var.name))
    error_message = "Storage account name can only include lowercase letters and numbers, with no hyphens or special characters."
  }
}
```

### Key Vault Name

```hcl
variable "name" {
  description = "Name of the key vault"
  type        = string
  default     = ""  # If using auto-generation logic

  validation {
    condition     = var.name == "" || (length(var.name) >= 3 && length(var.name) <= 24)
    error_message = "Key vault name must be between 3 and 24 characters when provided."
  }

  validation {
    condition     = var.name == "" || can(regex("^[a-zA-Z0-9-]+$", var.name))
    error_message = "Key vault name can only include alphanumeric characters and hyphens."
  }
}
```

### Virtual Network Name

```hcl
variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string

  validation {
    condition     = length(var.vnet_name) >= 2 && length(var.vnet_name) <= 64
    error_message = "VNet name must be between 2 and 64 characters."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.]+$", var.vnet_name))
    error_message = "VNet name can only include alphanumeric, hyphen, underscore, and period characters."
  }
}
```

### CIDR Blocks/Address Spaces

```hcl
variable "address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.address_space) > 0
    error_message = "At least one address space CIDR must be provided."
  }

  validation {
    condition = alltrue([
      for cidr in var.address_space : can(cidrnetmask(cidr))
    ])
    error_message = "All address space values must be valid CIDR notation."
  }

  validation {
    condition = alltrue([
      for cidr in var.address_space : tonumber(split("/", cidr)[1]) >= 8 && tonumber(split("/", cidr)[1]) <= 28
    ])
    error_message = "Address space CIDR prefix must be between /8 and /28."
  }
}
```

### SKU/Tier Values

```hcl
variable "sku_name" {
  description = "SKU name for the resource"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], lower(var.sku_name))
    error_message = "SKU name must be either 'standard' or 'premium'."
  }
}
```

### Tags

```hcl
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
```

### Numeric Ranges

```hcl
variable "retention_in_days" {
  description = "The number of days to retain data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "The retention period must be between 30 and 730 days."
  }
}
```

### Complex Objects with Nested Validation

```hcl
variable "network_rules" {
  description = "Network rules for the resource"
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
```

### IP Address Validation

```hcl
variable "dns_servers" {
  description = "List of DNS servers to use"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.dns_servers : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))
    ]) || length(var.dns_servers) == 0
    error_message = "DNS servers must be valid IPv4 addresses."
  }

  validation {
    condition = alltrue([
      for ip in var.dns_servers :
      tonumber(split(".", ip)[0]) <= 255 &&
      tonumber(split(".", ip)[1]) <= 255 &&
      tonumber(split(".", ip)[2]) <= 255 &&
      tonumber(split(".", ip)[3]) <= 255
    ]) || length(var.dns_servers) == 0
    error_message = "DNS server IP octets must be between 0 and 255."
  }
}
```

## Implementation Checklist

When implementing a new module or reviewing an existing one, ensure:

1. All required variables have appropriate validation blocks
2. Common patterns like resource names, CIDRs, and locations use the standard validation
3. Map and list objects with nested elements include proper validation for each element
4. Complex object structures have validation for their key attributes
5. Optional variables include sensible defaults
6. Variable descriptions are clear and explain the purpose and constraints 