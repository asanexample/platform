/**
 * Variables for the AKS Cluster module
 *
 * This file contains all input variables for the AKS cluster module
 * with comprehensive validation to ensure proper configurations.
 */

# Naming Components
variable "name_components" {
  description = "Components to auto-generate the cluster name if 'name' is not provided"
  type = object({
    prefix      = optional(string, "vip")
    environment = optional(string, "dev")
    region_abbv = optional(string, "eus")
    instance    = optional(string, "001")
  })
  default = {}
}

variable "name" {
  description = "Name of the AKS cluster (if custom naming is required). If not provided, it will be auto-generated based on naming components."
  type        = string
  default     = ""

  validation {
    condition     = var.name == "" || (length(var.name) >= 3 && length(var.name) <= 63)
    error_message = "Cluster name must be between 3 and 63 characters when provided."
  }

  validation {
    condition     = var.name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name))
    error_message = "Cluster name can only include alphanumeric characters, hyphens, and cannot end with a hyphen."
  }
}

# Resource Group Information
variable "resource_group_name" {
  description = "Name of the resource group to deploy the AKS cluster in"
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
  description = "Azure region where the AKS cluster will be deployed"
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

# Basic Cluster Configuration
variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = null

  validation {
    condition     = var.dns_prefix == null || (length(var.dns_prefix) >= 3 && length(var.dns_prefix) <= 63)
    error_message = "DNS prefix must be between 3 and 63 characters."
  }

  validation {
    condition     = var.dns_prefix == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.dns_prefix))
    error_message = "DNS prefix can only include alphanumeric characters, hyphens, and cannot end with a hyphen."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the AKS cluster"
  type        = string
  default     = null # Will use the default version provided by Azure

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version must be in the format of X.Y.Z."
  }
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

  validation {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "SKU tier must be either 'Free' or 'Standard'."
  }
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

# Node Pool Configuration
variable "default_nodepool_name" {
  description = "Name of the default node pool"
  type        = string
  default     = "system"

  validation {
    condition     = length(var.default_nodepool_name) >= 1 && length(var.default_nodepool_name) <= 12
    error_message = "Default node pool name must be between 1 and 12 characters."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.default_nodepool_name))
    error_message = "Default node pool name can only include lowercase alphanumeric characters and must start with a letter."
  }
}

variable "default_nodepool_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 3

  validation {
    condition     = var.default_nodepool_count >= 1 && var.default_nodepool_count <= 1000
    error_message = "Default node pool count must be between 1 and 1000."
  }
}

variable "default_nodepool_vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v4"
}

variable "default_nodepool_min_count" {
  description = "Minimum number of nodes for the default node pool when using auto scaling"
  type        = number
  default     = 1

  validation {
    condition     = var.default_nodepool_min_count >= 1 && var.default_nodepool_min_count <= 1000
    error_message = "Default node pool min count must be between 1 and 1000."
  }
}

variable "default_nodepool_max_count" {
  description = "Maximum number of nodes for the default node pool when using auto scaling"
  type        = number
  default     = 5

  validation {
    condition     = var.default_nodepool_max_count >= 1 && var.default_nodepool_max_count <= 1000
    error_message = "Default node pool max count must be between 1 and 1000."
  }
}

variable "nodepool_subnet_id" {
  description = "Subnet ID for the node pools"
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[a-f0-9-]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.nodepool_subnet_id))
    error_message = "Node pool subnet ID must be a valid Azure subnet resource ID."
  }
}

variable "zones" {
  description = "Availability zones for the node pools"
  type        = list(string)
  default     = ["1", "2", "3"]

  validation {
    condition     = alltrue([for z in var.zones : contains(["1", "2", "3"], z)])
    error_message = "Availability zones can only be 1, 2, or 3."
  }
}

# Application Node Pool
variable "create_app_nodepool" {
  description = "Whether to create an additional node pool for applications"
  type        = bool
  default     = true
}

variable "app_nodepool_name" {
  description = "Name of the application node pool"
  type        = string
  default     = "apps"

  validation {
    condition     = length(var.app_nodepool_name) >= 1 && length(var.app_nodepool_name) <= 12
    error_message = "Application node pool name must be between 1 and 12 characters."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*$", var.app_nodepool_name))
    error_message = "Application node pool name can only include lowercase alphanumeric characters and must start with a letter."
  }
}

variable "app_nodepool_vm_size" {
  description = "VM size for the application node pool"
  type        = string
  default     = "Standard_D4s_v4"
}

variable "app_nodepool_count" {
  description = "Initial number of nodes in the application node pool"
  type        = number
  default     = 2

  validation {
    condition     = var.app_nodepool_count >= 0 && var.app_nodepool_count <= 1000
    error_message = "Application node pool count must be between 0 and 1000."
  }
}

variable "app_nodepool_min_count" {
  description = "Minimum number of nodes for the application node pool when using auto scaling"
  type        = number
  default     = 1

  validation {
    condition     = var.app_nodepool_min_count >= 0 && var.app_nodepool_min_count <= 1000
    error_message = "Application node pool min count must be between 0 and 1000."
  }
}

variable "app_nodepool_max_count" {
  description = "Maximum number of nodes for the application node pool when using auto scaling"
  type        = number
  default     = 10

  validation {
    condition     = var.app_nodepool_max_count >= 1 && var.app_nodepool_max_count <= 1000
    error_message = "Application node pool max count must be between 1 and 1000."
  }
}

# Access Configuration
variable "azure_rbac_enabled" {
  description = "Enable Azure RBAC for Kubernetes authorization"
  type        = bool
  default     = true
}

variable "admin_group_object_ids" {
  description = "AD group object IDs that will have admin access to the AKS cluster"
  type        = list(string)
  default     = []
}

# Network Configuration
variable "network_plugin" {
  description = "Network plugin to use for the AKS cluster. Use 'none' for Bring Your Own CNI."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["azure", "kubenet", "none"], var.network_plugin)
    error_message = "Network plugin must be 'azure', 'kubenet', or 'none'."
  }
}

variable "network_plugin_mode" {
  description = "Network plugin mode when using Azure CNI. Only valid with network_plugin=azure."
  type        = string
  default     = null

  validation {
    condition     = var.network_plugin_mode == null || contains(["", "overlay"], var.network_plugin_mode)
    error_message = "Network plugin mode must be null, empty string, or 'overlay'."
  }
}

variable "network_policy" {
  description = "Network policy to use for the AKS cluster"
  type        = string
  default     = null

  validation {
    condition     = var.network_policy == null || contains(["azure", "calico"], var.network_policy)
    error_message = "Network policy must be 'azure' or 'calico'."
  }
}

variable "network_data_plane" {
  description = "The network data plane option to use"
  type        = string
  default     = null

  validation {
    condition     = var.network_data_plane == null || contains(["cilium"], var.network_data_plane)
    error_message = "Network data plane must be 'cilium' if specified."
  }
}

variable "private_cluster_enabled" {
  description = "Whether to create the cluster as a private cluster or not."
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "The ID of the Private DNS Zone which should be delegated to this Cluster."
  type        = string
  default     = "System"
  validation {
    condition     = contains(["System", "None"], var.private_dns_zone_id) || startswith(var.private_dns_zone_id, "/subscriptions/")
    error_message = "Private DNS Zone ID must be 'System', 'None', or a valid resource ID."
  }
}

# Monitoring Configuration
variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace to use for monitoring"
  type        = string
  
  validation {
    condition     = can(regex("^/subscriptions/[a-f0-9-]+/resourceGroups/[^/]+/providers/Microsoft.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "Log Analytics workspace ID must be a valid Azure resource ID."
  }
}

variable "monitor_workspace_id" {
  description = "ID of the Azure Monitor workspace to use for Prometheus metrics"
  type        = string
  
  validation {
    condition     = can(regex("^/subscriptions/[a-f0-9-]+/resourceGroups/[^/]+/providers/Microsoft.Monitor/accounts/[^/]+$", var.monitor_workspace_id))
    error_message = "Monitor workspace ID must be a valid Azure resource ID."
  }
}

# Identity Configurations
variable "aks_identity_name" {
  description = "Name of the user assigned identity for the AKS cluster"
  type        = string
  default     = null
}

variable "cert_manager_identity_name" {
  description = "Name of the user assigned identity for cert-manager"
  type        = string
  default     = null
}

variable "cert_manager_federated_credential_name" {
  description = "Name of the federated identity credential for cert-manager"
  type        = string
  default     = null
}

variable "karpenter_identity_name" {
  description = "Name of the user assigned identity for Karpenter"
  type        = string
  default     = null
}

variable "karpenter_federated_credential_name" {
  description = "Name of the federated identity credential for Karpenter"
  type        = string
  default     = null
}

# Routing Configuration
variable "private_route_table_name" {
  description = "Name of the private route table"
  type        = string
  default     = null
}

variable "vnet_resource_group_name" {
  description = "Name of the resource group containing the VNet"
  type        = string
  default     = null
}

# Diagnostic Settings
variable "diagnostic_setting_name" {
  description = "Name of the diagnostic setting for the AKS cluster"
  type        = string
  default     = null
}

# Data Collection for Monitoring
variable "streams" {
  description = "List of streams for data collection"
  type        = list(string)
  default     = ["Microsoft-ContainerLog", "Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory", "Microsoft-KubeNodeInventory", "Microsoft-KubePVInventory", "Microsoft-KubeServices", "Microsoft-KubeMonAgentEvents", "Microsoft-InsightsMetrics", "Microsoft-ComputerChangeTracking"]
}

variable "syslog_facilities" {
  description = "List of syslog facilities to collect"
  type        = list(string)
  default     = ["daemon", "syslog", "user", "local0"]
}

variable "syslog_levels" {
  description = "List of syslog levels to collect"
  type        = list(string)
  default     = ["Debug", "Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
}

variable "data_collection_interval" {
  description = "Data collection interval in seconds"
  type        = string
  default     = "1m"
}

variable "namespace_filtering_mode_for_data_collection" {
  description = "Namespace filtering mode for data collection"
  type        = string
  default     = "Include"

  validation {
    condition     = contains(["Include", "Exclude"], var.namespace_filtering_mode_for_data_collection)
    error_message = "Namespace filtering mode must be 'Include' or 'Exclude'."
  }
}

variable "namespaces_for_data_collection" {
  description = "List of namespaces to include or exclude for data collection"
  type        = list(string)
  default     = []
}

variable "enableContainerLogV2" {
  description = "Enable Container Log V2"
  type        = bool
  default     = true
}

# Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# API Server Access Profile variables
variable "authorized_ip_ranges" {
  description = "The IP ranges to allow for incoming traffic to the API server."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for ip in var.authorized_ip_ranges : can(cidrnetmask(ip))])
    error_message = "Each authorized IP range must be a valid CIDR notation."
  }
}

variable "private_cluster_public_fqdn_enabled" {
  description = "Whether to create additional public FQDN for private cluster or not."
  type        = bool
  default     = false
} 