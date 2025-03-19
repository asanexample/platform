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
  description = "Network plugin to use for the AKS cluster (azure, kubenet, or none)"
  type        = string
  default     = "azure"
}

variable "network_plugin_mode" {
  description = "Network plugin mode to use for the AKS cluster (overlay or transparent)"
  type        = string
  default     = "overlay"
}

variable "network_policy" {
  description = "Network policy to use for the AKS cluster (azure, calico)"
  type        = string
  default     = "azure"
}

variable "network_data_plane" {
  description = "Network data plane to use for the AKS cluster (azure, cilium)"
  type        = string
  default     = "azure"
}

variable "pod_cidr" {
  description = "CIDR range for pods"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR range for services"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address within the service CIDR for DNS service"
  type        = string
  default     = "10.0.0.10"
}

variable "docker_bridge_cidr" {
  description = "CIDR range for the Docker bridge network"
  type        = string
  default     = "172.17.0.1/16"
}

variable "subnet_id" {
  description = "ID of the subnet where the AKS cluster will be deployed"
  type        = string
  default     = null
}

variable "availability_zones" {
  description = "A list of availability zones to deploy the AKS cluster across"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "az_subnet_ids" {
  description = "Map of availability zone to subnet ID where AKS nodes should be deployed (follows allocations.csv topology)"
  type        = map(string)
  default     = {}
}

variable "use_network_topology" {
  description = "Whether to use the network topology defined in allocations.csv (if true, pod_cidr, service_cidr and dns_service_ip will be derived from the topology)"
  type        = bool
  default     = false
}

variable "network_topology_region" {
  description = "The region to use for network topology lookup in allocations.csv (e.g., eastus, westus)"
  type        = string
  default     = ""
}

variable "private_cluster_enabled" {
  description = "Enable private cluster for the AKS cluster"
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "ID of the private DNS zone for the AKS cluster"
  type        = string
  default     = null
}

variable "private_cluster_public_fqdn_enabled" {
  description = "Enable public FQDN for a private cluster"
  type        = bool
  default     = false
}

variable "authorized_ip_ranges" {
  description = "List of authorized IP ranges for the AKS cluster API"
  type        = list(string)
  default     = []
}

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

# Monitoring Configuration
variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for AKS monitoring"
  type        = string
  default     = null
}

# Application Node Pool
variable "app_node_pool_enabled" {
  description = "Enable application node pool"
  type        = bool
  default     = true
}

variable "app_node_pool_name" {
  description = "Name of the application node pool"
  type        = string
  default     = "app"
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