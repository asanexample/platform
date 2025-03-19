/**
 * # AKS Identity Module - Variables
 *
 * This module creates and configures user-assigned managed identities for AKS clusters and workloads.
 */

# ---------------------------------------------------------------------------------------------------------------------
# NAMING AND GENERAL VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "prefix" {
  description = "The prefix to use for generated resource names"
  type        = string
  default     = "centric"
  validation {
    condition     = length(var.prefix) <= 10
    error_message = "The prefix can be at most 10 characters."
  }
}

variable "customer" {
  description = "The customer identifier"
  type        = string
  default     = null
  validation {
    condition     = var.customer == null ? true : length(var.customer) <= 15
    error_message = "The customer identifier can be at most 15 characters."
  }
}

variable "stage" {
  description = "The environment stage (e.g., dev, test, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.stage)
    error_message = "Stage must be one of: dev, test, staging, prod."
  }
}

variable "region_abbv" {
  description = "The abbreviated region name"
  type        = string
  default     = "weu"
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
}

variable "location" {
  description = "The Azure location where the identities will be deployed"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# IDENTITY CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "cluster_name" {
  description = "The name of the AKS cluster the identities are for"
  type        = string
}

variable "aks_identity_name" {
  description = "The name of the AKS cluster identity. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "create_workload_identities" {
  description = "Whether to create workload identities for common services like cert-manager and karpenter"
  type        = bool
  default     = false
}

variable "workload_identity_enabled" {
  description = "Whether workload identity is enabled on the AKS cluster"
  type        = bool
  default     = false
}

variable "oidc_issuer_enabled" {
  description = "Whether OIDC issuer is enabled on the AKS cluster"
  type        = bool
  default     = false
}

variable "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  type        = string
  default     = null
}

variable "node_resource_group_id" {
  description = "The ID of the node resource group created by AKS"
  type        = string
  default     = null
}

variable "cert_manager_identity_name" {
  description = "The name of the cert-manager identity. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "cert_manager_federated_credential_name" {
  description = "The name of the cert-manager federated credential. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "karpenter_identity_name" {
  description = "The name of the karpenter identity. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "karpenter_federated_credential_name" {
  description = "The name of the karpenter federated credential. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "The ID of the subnet where the AKS cluster is deployed"
  type        = string
  default     = null
}

variable "private_route_table_name" {
  description = "The name of the private route table used by the AKS cluster"
  type        = string
  default     = null
}

variable "vnet_resource_group_name" {
  description = "The resource group name containing the VNet and route table"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------------------------------------------------
# TAGGING
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
} 