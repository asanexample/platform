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

# DNS Information
variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = null
}

# Kubernetes Configuration
variable "kubernetes_version" {
  description = "Kubernetes version to use for the AKS cluster"
  type        = string
  default     = null
}

variable "local_account_disabled" {
  description = "Whether to disable local accounts"
  type        = bool
  default     = false
}

variable "sku_tier" {
  description = "SKU tier for the AKS cluster (Free or Standard)"
  type        = string
  default     = "Free"
}

variable "workload_identity_enabled" {
  description = "Whether to enable Azure Workload Identity"
  type        = bool
  default     = false
}

variable "oidc_issuer_enabled" {
  description = "Whether to enable OIDC issuer"
  type        = bool
  default     = false
}

# Network Configuration
variable "network_plugin" {
  description = "The CNI plugin to use for networking (azure, kubenet, none)"
  type        = string
  default     = "azure"
}

variable "network_plugin_mode" {
  description = "The CNI network plugin mode (overlay or empty string)"
  type        = string
  default     = null
}

variable "network_policy" {
  description = "The network policy to use (azure, calico, none)"
  type        = string
  default     = null
}

variable "network_data_plane" {
  description = "The network data plane to use (azurecni or cilium)"
  type        = string
  default     = "azurecni"
}

variable "pod_cidr" {
  description = "The CIDR to use for pod IPs"
  type        = string
  default     = null
}

variable "service_cidr" {
  description = "The CIDR to use for Kubernetes services"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address within the Kubernetes service address range that will be used for kube-dns"
  type        = string
  default     = ""
}

variable "docker_bridge_cidr" {
  description = "The CIDR to use for the Docker bridge"
  type        = string
  default     = "172.17.0.1/16"
}

variable "subnet_id" {
  description = "The subnet ID to use for the AKS cluster"
  type        = string
  default     = null
}

variable "availability_zones" {
  description = "List of availability zones to use for the default node pool"
  type        = list(string)
  default     = []
}

variable "az_subnet_ids" {
  description = "Map of availability zone to subnet ID for AKS node pools"
  type        = map(string)
  default     = {}
}

variable "use_network_topology" {
  description = "Whether to use network topology for subnet allocation"
  type        = bool
  default     = false
}

variable "network_topology_region" {
  description = "The region to use for network topology (used for generating subnet names)"
  type        = string
  default     = null
}

variable "private_cluster_enabled" {
  description = "Whether to create a private AKS cluster"
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "The ID of the private DNS zone for the private AKS cluster"
  type        = string
  default     = null
}

variable "private_cluster_public_fqdn_enabled" {
  description = "Whether to enable public FQDN for the private AKS cluster"
  type        = bool
  default     = false
}

variable "authorized_ip_ranges" {
  description = "List of authorized IP ranges for the AKS API server"
  type        = list(string)
  default     = null
}

# Default Node Pool Configuration
variable "default_nodepool_name" {
  description = "Name of the default node pool"
  type        = string
  default     = "system"
}

variable "default_nodepool_vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "default_nodepool_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 1
}

# Identity Configuration
variable "identity_type" {
  description = "Type of identity to use for the AKS cluster (SystemAssigned, UserAssigned or SystemAssigned, UserAssigned)"
  type        = string
  default     = "UserAssigned"
}

variable "user_assigned_identity_id" {
  description = "ID of the user-assigned identity to use for the AKS cluster (if identity_type is UserAssigned)"
  type        = string
  default     = null
}

# Log Analytics Configuration
variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace to use for AKS monitoring"
  type        = string
  default     = null
}

# App Node Pool Configuration
variable "app_node_pool_enabled" {
  description = "Whether to create an additional node pool for applications"
  type        = bool
  default     = false
}

variable "app_node_pool_name" {
  description = "Name of the app node pool"
  type        = string
  default     = "app"
}

variable "app_node_pool_vm_size" {
  description = "VM size for the app node pool"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "app_node_pool_node_count" {
  description = "Number of nodes in the app node pool"
  type        = number
  default     = 1
}

variable "app_node_pool_max_pods" {
  description = "Maximum number of pods per node in the app node pool"
  type        = number
  default     = 110
}

variable "app_node_pool_os_disk_size_gb" {
  description = "OS disk size (in GB) for the app node pool VMs"
  type        = number
  default     = 128
}

variable "app_node_pool_enable_auto_scaling" {
  description = "Whether to enable auto-scaling for the app node pool"
  type        = bool
  default     = false
}

variable "app_node_pool_min_count" {
  description = "Minimum number of nodes in the app node pool when auto-scaling is enabled"
  type        = number
  default     = 1
}

variable "app_node_pool_max_count" {
  description = "Maximum number of nodes in the app node pool when auto-scaling is enabled"
  type        = number
  default     = 5
}

variable "app_node_pool_node_labels" {
  description = "Labels to apply to nodes in the app node pool"
  type        = map(string)
  default     = {}
}

# VNet and Route Table Configuration
variable "vnet_resource_group_name" {
  description = "Name of the resource group containing the VNet and route tables"
  type        = string
  default     = null
}

variable "private_route_table_name" {
  description = "Name of the private route table to assign to the AKS identity"
  type        = string
  default     = null
}

# Two-phase deployment configuration (deprecated)
variable "deployment_mode" {
  description = "DEPRECATED: The deployment mode variable is no longer used with the unified identities approach. It's kept for backward compatibility."
  type        = string
  default     = "full"
}

# Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
} 