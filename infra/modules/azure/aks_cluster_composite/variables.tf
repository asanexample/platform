/**
 * Variables for the AKS Cluster Composite module
 *
 * This module combines various specialized AKS modules to create a complete solution.
 */

# Naming module variables
variable "prefix" {
  description = "The prefix to use for all resources"
  type        = string
  default     = "centric"
}

variable "customer" {
  description = "The customer name to use in resource naming"
  type        = string
  default     = "shared"
}

variable "stage" {
  description = "The environment stage (e.g., dev, preprod, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.stage)
    error_message = "Stage must be one of: dev, test, staging, prod."
  }
}

variable "region_abbv" {
  description = "The abbreviated Azure region name (e.g., wus, eus, neu)"
  type        = string
  default     = "weu"
}

# Override name (if custom naming is required)
variable "name" {
  description = "Name of the AKS cluster (if custom naming is required). If not provided, it will be auto-generated."
  type        = string
  default     = ""
}

# Resource Group Information
variable "resource_group_name" {
  description = "Name of the resource group to deploy the AKS cluster in"
  type        = string
}

variable "location" {
  description = "Azure region where the AKS cluster will be deployed"
  type        = string
}

# Basic Cluster Configuration
variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the AKS cluster"
  type        = string
  default     = null
}

variable "local_account_disabled" {
  description = "Disable local accounts for the AKS cluster"
  type        = bool
  default     = true
}

variable "sku_tier" {
  description = "SKU tier for the AKS cluster (Free or Standard)"
  type        = string
  default     = "Free"
}

variable "workload_identity_enabled" {
  description = "Enable workload identity for the AKS cluster"
  type        = bool
  default     = true
}

variable "oidc_issuer_enabled" {
  description = "Enable OIDC issuer for the AKS cluster"
  type        = bool
  default     = true
}

# Network Configuration
variable "network_plugin" {
# Default Node Pool
variable "default_nodepool_name" {
  description = "Name of the default node pool"
  type        = string
  default     = "system"
}

variable "default_nodepool_vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v4"
}

variable "default_nodepool_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 1
}

# Identity Configuration
variable "identity_type" {
  description = "Type of identity to use for the AKS cluster"
  type        = string
  default     = "SystemAssigned"
}

variable "user_assigned_identity_id" {
  description = "ID of the user-assigned managed identity for the AKS cluster"
  type        = string
  default     = null
}

# Application Node Pool
variable "app_node_pool_enabled" {
  description = "Enable application node pool"
  type        = bool
  default     = true
}

variable "app_node_pool_vm_size" {
  description = "VM size for the application node pool"
  type        = string
  default     = "Standard_D4s_v4"
}

variable "app_node_pool_node_count" {
  description = "Initial number of nodes in the application node pool"
  type        = number
  default     = 2
}

variable "app_node_pool_max_pods" {
  description = "Maximum number of pods that can run on a node in the application node pool"
  type        = number
  default     = 30
}

variable "app_node_pool_os_disk_size_gb" {
  description = "OS disk size for nodes in the application node pool"
  type        = number
  default     = 128
}

variable "app_node_pool_enable_auto_scaling" {
  description = "Enable auto-scaling for the application node pool"
  type        = bool
  default     = true
}

variable "app_node_pool_min_count" {
  description = "Minimum node count for auto-scaling"
  type        = number
  default     = 1
}

variable "app_node_pool_max_count" {
  description = "Maximum node count for auto-scaling"
  type        = number
  default     = 5
}

variable "app_node_pool_node_labels" {
  description = "Labels to apply to nodes in the application node pool"
  type        = map(string)
  default     = {
    "nodepool" = "apps"
    "app"      = "true"
  }
}

# Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
} 