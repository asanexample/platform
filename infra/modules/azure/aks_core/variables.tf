/**
 * # AKS Core Module - Variables
 *
 * Core module responsible for creating the base AKS cluster with essential components.
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
  default     = "shared"
  validation {
    condition     = length(var.customer) <= 15
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

variable "name" {
  description = "The name of the AKS cluster. If not specified, a name will be generated."
  type        = string
  default     = null
  validation {
    condition     = var.name == null ? true : length(var.name) >= 3 && length(var.name) <= 24
    error_message = "The name must be between 3 and 24 characters."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE GROUP AND LOCATION
# ---------------------------------------------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "The resource group name where the AKS cluster will be created"
  type        = string
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "The resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "The Azure location where the AKS cluster will be deployed"
  type        = string
  validation {
    condition     = contains([
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
    error_message = "Invalid Azure location. Please check available locations."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CLUSTER CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = null
  validation {
    condition     = var.dns_prefix == null ? true : length(var.dns_prefix) >= 3 && length(var.dns_prefix) <= 45
    error_message = "The DNS prefix must be between 3 and 45 characters."
  }
}

variable "kubernetes_version" {
  description = "The Kubernetes version for the AKS cluster"
  type        = string
  default     = null
}

variable "local_account_disabled" {
  description = "Whether local accounts are disabled for the AKS cluster"
  type        = bool
  default     = true
}

variable "sku_tier" {
  description = "The SKU tier for the AKS cluster (Free or Standard)"
  type        = string
  default     = "Free"
  validation {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "The SKU tier must be either Free or Standard."
  }
}

variable "private_cluster_enabled" {
  description = "Whether the AKS cluster is a private cluster"
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "The ID of the Private DNS Zone for private cluster"
  type        = string
  default     = null
}

variable "workload_identity_enabled" {
  description = "Whether workload identity is enabled for the AKS cluster"
  type        = bool
  default     = true
}

variable "oidc_issuer_enabled" {
  description = "Whether OIDC issuer is enabled for the AKS cluster"
  type        = bool
  default     = true
}

variable "authorized_ip_ranges" {
  description = "The IP ranges authorized for API server access"
  type        = list(string)
  default     = null
}

# ---------------------------------------------------------------------------------------------------------------------
# DEFAULT NODE POOL
# ---------------------------------------------------------------------------------------------------------------------

variable "default_nodepool_name" {
  description = "The name of the default node pool"
  type        = string
  default     = "system"
  validation {
    condition     = length(var.default_nodepool_name) >= 1 && length(var.default_nodepool_name) <= 12
    error_message = "The default node pool name must be between 1 and 12 characters."
  }
}

variable "default_nodepool_vm_size" {
  description = "The VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "default_nodepool_count" {
  description = "The node count for the default node pool"
  type        = number
  default     = 2
  validation {
    condition     = var.default_nodepool_count >= 1 && var.default_nodepool_count <= 100
    error_message = "The default node pool count must be between 1 and 100."
  }
}

variable "default_nodepool_enable_auto_scaling" {
  description = "Whether auto-scaling is enabled for the default node pool"
  type        = bool
  default     = true
}

variable "default_nodepool_min_count" {
  description = "The minimum node count for the default node pool auto-scaling"
  type        = number
  default     = 1
  validation {
    condition     = var.default_nodepool_min_count >= 1 && var.default_nodepool_min_count <= 100
    error_message = "The default node pool minimum count must be between 1 and 100."
  }
}

variable "default_nodepool_max_count" {
  description = "The maximum node count for the default node pool auto-scaling"
  type        = number
  default     = 3
  validation {
    condition     = var.default_nodepool_max_count >= 1 && var.default_nodepool_max_count <= 100
    error_message = "The default node pool maximum count must be between 1 and 100."
  }
}

variable "default_nodepool_max_pods" {
  description = "The maximum number of pods per node for the default node pool"
  type        = number
  default     = 30
  validation {
    condition     = var.default_nodepool_max_pods >= 30 && var.default_nodepool_max_pods <= 250
    error_message = "The default node pool maximum pods must be between 30 and 250."
  }
}

variable "default_nodepool_os_disk_size_gb" {
  description = "The OS disk size in GB for the default node pool"
  type        = number
  default     = 128
  validation {
    condition     = var.default_nodepool_os_disk_size_gb >= 30 && var.default_nodepool_os_disk_size_gb <= 2048
    error_message = "The default node pool OS disk size must be between 30 and 2048 GB."
  }
}

variable "default_nodepool_node_labels" {
  description = "The node labels for the default node pool"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------------------------------------
# IDENTITY CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "identity_type" {
  description = "The type of identity to use for the AKS cluster"
  type        = string
  default     = "UserAssigned"
  validation {
    condition     = contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity_type)
    error_message = "The identity type must be one of: SystemAssigned, UserAssigned, or 'SystemAssigned, UserAssigned'."
  }
}

variable "user_assigned_identity_id" {
  description = "The ID of the user-assigned identity for the AKS cluster"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------------------------------------------------
# NETWORK CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "network_plugin" {
  description = "The network plugin to use for the AKS cluster"
  type        = string
  default     = "azure"
  validation {
    condition     = contains(["azure", "kubenet", "none"], var.network_plugin)
    error_message = "The network plugin must be one of: azure, kubenet, none."
  }
}

variable "network_policy" {
  description = "The network policy to use for the AKS cluster"
  type        = string
  default     = "azure"
  validation {
    condition     = contains(["azure", "calico"], var.network_policy)
    error_message = "The network policy must be one of: azure, calico."
  }
}

variable "pod_cidr" {
  description = "The CIDR for pod IPs when using kubenet"
  type        = string
  default     = null
}

variable "service_cidr" {
  description = "The CIDR for Kubernetes services"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "The IP address for the DNS service"
  type        = string
  default     = "10.0.0.10"
}

variable "docker_bridge_cidr" {
  description = "The CIDR for the Docker bridge network"
  type        = string
  default     = "172.17.0.1/16"
}

variable "subnet_id" {
  description = "The ID of the subnet where the AKS cluster will be deployed"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------------------------------------------------
# MONITORING CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace for container insights"
  type        = string
  default     = null
}

variable "enable_azure_policy" {
  description = "Whether Azure Policy is enabled for the AKS cluster"
  type        = bool
  default     = true
}

variable "enable_host_encryption" {
  description = "Whether host encryption is enabled for the AKS cluster"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# TAGGING
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
} 