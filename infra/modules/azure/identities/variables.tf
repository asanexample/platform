/**
 * # Variables for the Azure Identities Module
 *
 * This file contains all the variables needed for the Azure Identities module.
 */

# -----------------------------------------------------------------------------
# NAMING AND GENERAL VARIABLES
# -----------------------------------------------------------------------------

variable "prefix" {
  description = "Naming prefix for resources."
  type        = string
  default     = ""

  validation {
    condition     = length(var.prefix) <= 10
    error_message = "The prefix should not be longer than 10 characters."
  }
}

variable "customer" {
  description = "Customer name (used for resource naming)."
  type        = string
  default     = null

  validation {
    condition     = var.customer == null ? true : length(var.customer) >= 2 && length(var.customer) <= 10
    error_message = "The customer name should be between 2 and 10 characters."
  }
}

variable "environment" {
  description = "Environment name (used for resource naming, ex: dev, qa, prod, ops)."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod", "ops"], var.environment)
    error_message = "The environment should be one of: dev, qa, prod, ops."
  }
}

variable "region_abbv" {
  description = "Region abbreviation for naming purposes."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# RESOURCE GROUP AND LOCATION
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the resource group where identities will be created."
  type        = string
}

variable "location" {
  description = "Azure region where identities will be created."
  type        = string
}

# -----------------------------------------------------------------------------
# AKS CLUSTER IDENTITY
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the AKS cluster these identities are associated with."
  type        = string
  default     = null
}

variable "create_aks_identity" {
  description = "Whether to create an identity for the AKS cluster."
  type        = bool
  default     = true
}

variable "aks_identity_name" {
  description = "Name for the AKS cluster identity. If not specified, will be derived from the cluster name."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# NETWORKING
# -----------------------------------------------------------------------------

variable "vnet_resource_group_name" {
  description = "Name of the resource group containing the VNet and route tables."
  type        = string
  default     = null
}

variable "private_route_table_name" {
  description = "Name of the private route table to assign to the AKS identity."
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "ID of the subnet to assign to the AKS identity."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# WORKLOAD IDENTITY
# -----------------------------------------------------------------------------

variable "enable_workload_identity" {
  description = "Whether to enable workload identity for the cluster."
  type        = bool
  default     = false
}

variable "create_federated_credentials" {
  description = "Whether to create federated credentials for workload identities. Set to false for first phase deployment."
  type        = bool
  default     = false
}

variable "create_role_assignments" {
  description = "Whether to create role assignments for workload identities. Set to false for first phase deployment."
  type        = bool
  default     = false
}

variable "aks_oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster. Required for federated credentials."
  type        = string
  default     = null
}

variable "node_resource_group_id" {
  description = "The ID of the node resource group for the AKS cluster. Required for role assignments."
  type        = string
  default     = null
}

variable "workload_identities" {
  description = "Map of workload identities to create, with their configurations."
  type = map(object({
    name            = optional(string)
    namespace       = string
    service_account = string
    roles           = list(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# TAGGING
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
} 