variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy the virtual network in"
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

variable "vnet_name" {
  description = "Name of the virtual network to create"
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

variable "subnets" {
  description = "Map of subnet names to configuration"
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
    delegation        = optional(map(list(map(string))), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, subnet in var.subnets : length(name) >= 1 && length(name) <= 80
    ])
    error_message = "Subnet names must be between 1 and 80 characters."
  }

  validation {
    condition = alltrue([
      for name, subnet in var.subnets : can(regex("^[a-zA-Z0-9-_.]+$", name))
    ])
    error_message = "Subnet names can only include alphanumeric, hyphen, underscore, and period characters."
  }

  validation {
    condition = alltrue([
      for name, subnet in var.subnets : length(subnet.address_prefixes) > 0
    ])
    error_message = "Each subnet must have at least one address prefix."
  }

  validation {
    condition = alltrue(flatten([
      for name, subnet in var.subnets : [
        for cidr in subnet.address_prefixes : can(cidrnetmask(cidr))
      ]
    ]))
    error_message = "All subnet address prefixes must be valid CIDR notation."
  }

  validation {
    condition = alltrue(flatten([
      for name, subnet in var.subnets : [
        for cidr in subnet.address_prefixes : tonumber(split("/", cidr)[1]) >= 8 && tonumber(split("/", cidr)[1]) <= 29
      ]
    ]))
    error_message = "Subnet CIDR prefixes must be between /8 and /29."
  }

  validation {
    condition = alltrue(flatten([
      for name, subnet in var.subnets : [
        for endpoint in subnet.service_endpoints : contains([
          "Microsoft.AzureActiveDirectory", "Microsoft.AzureCosmosDB", "Microsoft.ContainerRegistry",
          "Microsoft.EventHub", "Microsoft.KeyVault", "Microsoft.ServiceBus", "Microsoft.Sql",
          "Microsoft.Storage", "Microsoft.Web"
        ], endpoint)
      ] if length(subnet.service_endpoints) > 0
    ]))
    error_message = "Service endpoints must be valid Azure service endpoints."
  }
}

variable "dns_servers" {
  description = "List of DNS servers to use with the virtual network"
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

# AKS Networking Configuration Parameters
variable "enable_aks_networking" {
  description = "Whether to enable AKS-specific networking features"
  type        = bool
  default     = false
}

variable "aks_subnet_name" {
  description = "Name of the subnet to use for AKS nodes. Must match a key in the subnets map."
  type        = string
  default     = null
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster. Required if enable_aks_networking is true."
  type        = string
  default     = null
}

variable "aks_private_cluster_enabled" {
  description = "Whether the AKS cluster is private. This affects DNS zone creation."
  type        = bool
  default     = false
}

variable "aks_node_resource_group" {
  description = "Name of the resource group where AKS will create node resources"
  type        = string
  default     = null
}

variable "aks_private_dns_zone_id" {
  description = "ID of an existing private DNS zone for AKS. If not provided, a new one will be created if needed."
  type        = string
  default     = null
} 