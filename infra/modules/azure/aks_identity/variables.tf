/**
 * # AKS Identity Module - Variables
 *
 * This module creates and configures user-assigned managed identities for AKS clusters and workloads.
 */

# ---------------------------------------------------------------------------------------------------------------------
# NAMING AND GENERAL VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "prefix" {
  description = "The prefix to use for all resources"
  type        = string
  default     = "vip"
}

variable "environment" {
  description = "The environment (e.g. dev, test, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "ops"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, ops."
  }
}

variable "region_abbv" {
  description = "The abbreviated region name"
  type        = string
  default     = "weu"
  validation {
    condition     = length(var.region_abbv) >= 2 && length(var.region_abbv) <= 6
    error_message = "The region abbreviation must be between 2 and 6 characters."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE GROUP AND LOCATION
# ---------------------------------------------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "The resource group name where the identities will be created"
  type        = string
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "The resource group name must be between 1 and 90 characters."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.()]+$", var.resource_group_name))
    error_message = "Resource group name can only include alphanumeric, hyphen, underscore, parentheses, and period characters."
  }
}

variable "location" {
  description = "The Azure location where the identities will be deployed"
  type        = string
  validation {
    condition = contains([
      "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast",
      "brazilsouth", "brazilsoutheast",
      "canadacentral", "canadaeast",
      "centralindia", "centralus",
      "eastasia", "eastus", "eastus2",
      "francecentral", "francesouth",
      "germanynorth", "germanywestcentral",
      "japaneast", "japanwest",
      "koreacentral", "koreasouth",
      "northcentralus", "northeurope", "norwayeast", "norwaywest",
      "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "swedencentral", "switzerlandnorth", "switzerlandwest",
      "uaecentral", "uaenorth", "uksouth", "ukwest", "usnorth", "uswest", "uswest2", "uswest3",
      "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3"
    ], var.location)
    error_message = "The location must be a valid Azure region name."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# IDENTITY CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "cluster_name" {
  description = "The name of the AKS cluster the identities are for"
  type        = string
  validation {
    condition     = length(var.cluster_name) >= 3 && length(var.cluster_name) <= 63
    error_message = "The AKS cluster name must be between 3 and 63 characters."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.cluster_name))
    error_message = "The AKS cluster name can only include alphanumeric, hyphen, and underscore characters."
  }
}

variable "aks_identity_name" {
  description = "The name of the user-assigned managed identity for AKS"
  type        = string
  default     = null
  validation {
    condition     = var.aks_identity_name == null ? true : length(var.aks_identity_name) >= 3 && length(var.aks_identity_name) <= 128
    error_message = "The AKS identity name must be between 3 and 128 characters when provided."
  }
  validation {
    condition     = var.aks_identity_name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.aks_identity_name))
    error_message = "The AKS identity name can only include alphanumeric, hyphen, and underscore characters."
  }
}

variable "create_workload_identities" {
  description = "Whether to create workload identities for common services like cert-manager and karpenter"
  type        = bool
  default     = false
  validation {
    condition     = var.create_workload_identities != null
    error_message = "The create_workload_identities value must be either true or false."
  }
}

variable "workload_identity_enabled" {
  description = "Whether workload identity is enabled on the AKS cluster"
  type        = bool
  default     = false
  validation {
    condition     = var.workload_identity_enabled != null
    error_message = "The workload_identity_enabled value must be either true or false."
  }
}

variable "oidc_issuer_enabled" {
  description = "Whether OIDC issuer is enabled on the AKS cluster"
  type        = bool
  default     = false
  validation {
    condition     = var.oidc_issuer_enabled != null
    error_message = "The oidc_issuer_enabled value must be either true or false."
  }
}

variable "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  type        = string
  default     = null
  validation {
    condition     = var.oidc_issuer_url == null ? true : length(var.oidc_issuer_url) > 10
    error_message = "The OIDC issuer URL must be a valid URL when provided."
  }
  validation {
    condition     = var.oidc_issuer_url == null ? true : can(regex("^https://.*", var.oidc_issuer_url))
    error_message = "The OIDC issuer URL must start with 'https://' when provided."
  }
}

variable "node_resource_group_id" {
  description = "The ID of the node resource group created by AKS"
  type        = string
  default     = null
  validation {
    condition     = var.node_resource_group_id == null ? true : length(var.node_resource_group_id) > 20
    error_message = "The node resource group ID must be a valid Azure resource ID when provided."
  }
  validation {
    condition     = var.node_resource_group_id == null ? true : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.node_resource_group_id))
    error_message = "The node resource group ID must be in the format '/subscriptions/{subscription_id}/resourceGroups/{resource_group_name}'."
  }
}

variable "cert_manager_identity_name" {
  description = "The name of the cert-manager identity. If not provided, a name will be generated."
  type        = string
  default     = null
  validation {
    condition     = var.cert_manager_identity_name == null ? true : length(var.cert_manager_identity_name) >= 3 && length(var.cert_manager_identity_name) <= 128
    error_message = "The cert-manager identity name must be between 3 and 128 characters when provided."
  }
  validation {
    condition     = var.cert_manager_identity_name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.cert_manager_identity_name))
    error_message = "The cert-manager identity name can only include alphanumeric, hyphen, and underscore characters."
  }
}

variable "cert_manager_federated_credential_name" {
  description = "The name of the cert-manager federated credential. If not provided, a name will be generated."
  type        = string
  default     = null
  validation {
    condition     = var.cert_manager_federated_credential_name == null ? true : length(var.cert_manager_federated_credential_name) >= 3 && length(var.cert_manager_federated_credential_name) <= 128
    error_message = "The cert-manager federated credential name must be between 3 and 128 characters when provided."
  }
  validation {
    condition     = var.cert_manager_federated_credential_name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.cert_manager_federated_credential_name))
    error_message = "The cert-manager federated credential name can only include alphanumeric, hyphen, and underscore characters."
  }
}

variable "karpenter_identity_name" {
  description = "The name of the karpenter identity. If not provided, a name will be generated."
  type        = string
  default     = null
  validation {
    condition     = var.karpenter_identity_name == null ? true : length(var.karpenter_identity_name) >= 3 && length(var.karpenter_identity_name) <= 128
    error_message = "The karpenter identity name must be between 3 and 128 characters when provided."
  }
  validation {
    condition     = var.karpenter_identity_name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.karpenter_identity_name))
    error_message = "The karpenter identity name can only include alphanumeric, hyphen, and underscore characters."
  }
}

variable "karpenter_federated_credential_name" {
  description = "The name of the karpenter federated credential. If not provided, a name will be generated."
  type        = string
  default     = null
  validation {
    condition     = var.karpenter_federated_credential_name == null ? true : length(var.karpenter_federated_credential_name) >= 3 && length(var.karpenter_federated_credential_name) <= 128
    error_message = "The karpenter federated credential name must be between 3 and 128 characters when provided."
  }
  validation {
    condition     = var.karpenter_federated_credential_name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.karpenter_federated_credential_name))
    error_message = "The karpenter federated credential name can only include alphanumeric, hyphen, and underscore characters."
  }
}

variable "subnet_id" {
  description = "The ID of the subnet where the AKS cluster is deployed"
  type        = string
  default     = null
  validation {
    condition     = var.subnet_id == null ? true : length(var.subnet_id) > 20
    error_message = "The subnet ID must be a valid Azure resource ID when provided."
  }
  validation {
    condition     = var.subnet_id == null ? true : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "The subnet ID must be in the proper Azure resource ID format for subnets."
  }
}

variable "private_route_table_name" {
  description = "The name of the private route table used by the AKS cluster"
  type        = string
  default     = null
  validation {
    condition     = var.private_route_table_name == null ? true : length(var.private_route_table_name) >= 1 && length(var.private_route_table_name) <= 80
    error_message = "The route table name must be between 1 and 80 characters when provided."
  }
  validation {
    condition     = var.private_route_table_name == null ? true : can(regex("^[a-zA-Z0-9-_.]+$", var.private_route_table_name))
    error_message = "The route table name can only include alphanumeric, hyphen, underscore, and period characters."
  }
}

variable "vnet_resource_group_name" {
  description = "The resource group name containing the VNet and route table"
  type        = string
  default     = null
  validation {
    condition     = var.vnet_resource_group_name == null ? true : length(var.vnet_resource_group_name) >= 1 && length(var.vnet_resource_group_name) <= 90
    error_message = "The VNet resource group name must be between 1 and 90 characters when provided."
  }
  validation {
    condition     = var.vnet_resource_group_name == null ? true : can(regex("^[a-zA-Z0-9-_.()]+$", var.vnet_resource_group_name))
    error_message = "The VNet resource group name can only include alphanumeric, hyphen, underscore, parentheses, and period characters."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# TAGGING
# ---------------------------------------------------------------------------------------------------------------------

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