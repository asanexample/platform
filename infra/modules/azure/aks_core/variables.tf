/**
 * # AKS Core Module - Variables
 *
 * Core module responsible for creating the base AKS cluster with essential components.
 */

# ---------------------------------------------------------------------------------------------------------------------
# NAMING AND GENERAL VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "centric"
  validation {
    condition     = length(var.prefix) >= 3 && length(var.prefix) <= 10
    error_message = "The prefix must be between 3 and 10 characters."
  }
}

variable "environment" {
  description = "Environment name for resource tagging (dev, test, staging, prod, ops)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "ops"], var.environment)
    error_message = "The environment must be one of: dev, test, staging, prod, ops."
  }
}

variable "region_abbv" {
  description = "Abbreviation for region (used in resource naming)"
  type        = string
  default     = "weu"
  validation {
    condition     = length(var.region_abbv) >= 2 && length(var.region_abbv) <= 6
    error_message = "The region abbreviation must be between 2 and 6 characters."
  }
}

variable "name" {
  description = "Name of the AKS cluster resource. If null, a name should be provided by Terragrunt using the naming module."
  type        = string
  default     = null
  validation {
    condition     = var.name == null ? true : length(var.name) >= 3 && length(var.name) <= 63
    error_message = "The AKS cluster name must be between 3 and 63 characters."
  }
  validation {
    condition     = var.name == null ? true : can(regex("^[a-zA-Z0-9-_]+$", var.name))
    error_message = "The AKS cluster name can only include alphanumeric, hyphen, and underscore characters."
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
  validation {
    condition     = var.kubernetes_version == null ? true : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "The Kubernetes version must be in the format X.Y.Z (e.g., 1.24.0)."
  }
}

variable "automatic_channel_upgrade" {
  description = "The upgrade channel for this Kubernetes Cluster. Possible values are patch, rapid, node-image and stable."
  type        = string
  default     = "stable"
  validation {
    condition     = var.automatic_channel_upgrade == null ? true : contains(["patch", "rapid", "node-image", "stable", "none"], var.automatic_channel_upgrade)
    error_message = "The automatic_channel_upgrade must be one of: patch, rapid, node-image, stable, none."
  }
}

variable "local_account_disabled" {
  description = "If true, disable local accounts in Kubernetes"
  type        = bool
  default     = true
  validation {
    condition     = var.local_account_disabled != null
    error_message = "The local_account_disabled value must be either true or false."
  }
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
  validation {
    condition     = var.private_dns_zone_id == null ? true : length(var.private_dns_zone_id) > 20
    error_message = "The private DNS zone ID must be a valid Azure resource ID."
  }
}

variable "workload_identity_enabled" {
  description = "Enable or disable Workload Identity for the cluster"
  type        = bool
  default     = true
  validation {
    condition     = var.workload_identity_enabled != null
    error_message = "The workload_identity_enabled value must be either true or false."
  }
}

variable "oidc_issuer_enabled" {
  description = "Enable or disable the OIDC issuer URL"
  type        = bool
  default     = true
  validation {
    condition     = var.oidc_issuer_enabled != null
    error_message = "The oidc_issuer_enabled value must be either true or false."
  }
}

variable "authorized_ip_ranges" {
  description = "The IP ranges authorized for API server access"
  type        = list(string)
  default     = null
  validation {
    condition = var.authorized_ip_ranges == null ? true : alltrue([
      for ip_range in var.authorized_ip_ranges : can(cidrnetmask(ip_range))
    ])
    error_message = "Each authorized IP range must be a valid CIDR notation (e.g., 10.0.0.0/24)."
  }
}

variable "azure_active_directory_role_based_access_control" {
  description = "Azure Active Directory RBAC configuration for AKS"
  type = object({
    admin_group_object_ids = list(string)
    azure_rbac_enabled     = bool
  })
  default = null
  validation {
    condition = var.azure_active_directory_role_based_access_control == null ? true : (
      length(var.azure_active_directory_role_based_access_control.admin_group_object_ids) > 0
    )
    error_message = "At least one admin group object ID must be provided when Azure AD RBAC is configured."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEFAULT NODE POOL
# ---------------------------------------------------------------------------------------------------------------------

variable "default_nodepool_name" {
  description = "Name of the default node pool"
  type        = string
  default     = "system"
  validation {
    condition     = length(var.default_nodepool_name) >= 1 && length(var.default_nodepool_name) <= 12
    error_message = "The default node pool name must be between 1 and 12 characters."
  }
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.default_nodepool_name))
    error_message = "The default node pool name can only include lowercase alphanumeric characters."
  }
}

variable "default_nodepool_vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v3"
  validation {
    condition     = length(var.default_nodepool_vm_size) > 0
    error_message = "The default node pool VM size must not be empty."
  }
}

variable "default_nodepool_count" {
  description = "Initial node count for the default node pool"
  type        = number
  default     = 1
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
  description = "Minimum node count for the default node pool"
  type        = number
  default     = 1
  validation {
    condition     = var.default_nodepool_min_count >= 1 && var.default_nodepool_min_count <= 100
    error_message = "The default node pool minimum count must be between 1 and 100."
  }
}

variable "default_nodepool_max_count" {
  description = "Maximum node count for the default node pool"
  type        = number
  default     = 3
  validation {
    condition     = var.default_nodepool_max_count >= 1 && var.default_nodepool_max_count <= 100
    error_message = "The default node pool maximum count must be between 1 and 100."
  }
  validation {
    condition     = var.default_nodepool_max_count >= var.default_nodepool_min_count
    error_message = "The maximum node count must be greater than or equal to the minimum node count."
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
  description = "OS disk size in GB for the default node pool"
  type        = number
  default     = 128
  validation {
    condition     = var.default_nodepool_os_disk_size_gb >= 30 && var.default_nodepool_os_disk_size_gb <= 2048
    error_message = "The OS disk size must be between 30 and 2048 GB."
  }
}

variable "default_nodepool_node_labels" {
  description = "The node labels for the default node pool"
  type        = map(string)
  default     = {}
}

variable "default_nodepool_only_critical_addons_enabled" {
  description = "Whether to taint the default node pool with CriticalAddonsOnly=true:NoSchedule to ensure only critical addons are scheduled on it"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# IDENTITY CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "identity_type" {
  description = "The type of identity to use for the cluster"
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
  validation {
    condition     = var.user_assigned_identity_id == null ? true : length(var.user_assigned_identity_id) > 20
    error_message = "The user-assigned identity ID must be a valid Azure resource ID."
  }
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
  default     = null
  validation {
    condition     = var.network_policy == null ? true : contains(["azure", "calico", "none"], var.network_policy)
    error_message = "The network policy must be one of: azure, calico, none, or null."
  }
}

variable "outbound_type" {
  description = "The outbound (egress) routing method for the AKS cluster"
  type        = string
  default     = "loadBalancer"
  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.outbound_type)
    error_message = "The outbound type must be one of: loadBalancer, userDefinedRouting, managedNATGateway, userAssignedNATGateway."
  }
}

variable "pod_cidr" {
  description = "The CIDR for pod IPs when using kubenet"
  type        = string
  default     = null
  validation {
    condition     = var.pod_cidr == null ? true : can(cidrnetmask(var.pod_cidr))
    error_message = "The pod CIDR must be a valid CIDR notation (e.g., 10.244.0.0/16)."
  }
}

variable "service_cidr" {
  description = "The CIDR for Kubernetes services"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.service_cidr))
    error_message = "The service CIDR must be a valid CIDR notation (e.g., 10.0.0.0/16)."
  }
}

variable "dns_service_ip" {
  description = "The IP address for the DNS service"
  type        = string
  default     = "10.0.0.10"
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.dns_service_ip))
    error_message = "The DNS service IP must be a valid IPv4 address."
  }
}

variable "docker_bridge_cidr" {
  description = "The CIDR for the Docker bridge network"
  type        = string
  default     = "172.17.0.1/16"
  validation {
    condition     = can(cidrnetmask(var.docker_bridge_cidr))
    error_message = "The Docker bridge CIDR must be a valid CIDR notation (e.g., 172.17.0.1/16)."
  }
}

variable "subnet_id" {
  description = "The ID of the subnet where the AKS cluster will be deployed"
  type        = string
  default     = null
  validation {
    condition     = var.subnet_id == null ? true : length(var.subnet_id) > 20
    error_message = "The subnet ID must be a valid Azure resource ID."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# MONITORING CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace for container insights"
  type        = string
  default     = null
  validation {
    condition     = var.log_analytics_workspace_id == null ? true : length(var.log_analytics_workspace_id) > 20
    error_message = "The Log Analytics workspace ID must be a valid Azure resource ID."
  }
}

variable "prometheus_dcr_id" {
  description = "The ID of the Azure Monitor data collection rule for Prometheus metrics. If null and enable_prometheus_integration is true, integration will not be configured."
  type        = string
  default     = null
}

variable "monitor_workspace_id" {
  description = "The ID of the Azure Monitor Workspace where Prometheus metrics are sent. Required if enable_prometheus_integration is true."
  type        = string
  default     = null
}

variable "enable_prometheus_integration" {
  description = "Whether to enable the Azure Monitor managed service for Prometheus integration."
  type        = bool
  default     = true
}

variable "diagnostic_settings" {
  description = "A list of diagnostic settings to create for the AKS cluster"
  type = list(object({
    name                       = string
    log_analytics_workspace_id = string
    enabled_log_categories     = list(string)
    metric_categories          = list(string)
    log_retention_days         = optional(number)
  }))
  default = []
}

variable "create_kubeconfig" {
  description = "Whether to create a local kubeconfig file"
  type        = bool
  default     = false
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
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "role_assignments" {
  description = "A list of role assignments to create for the AKS cluster"
  type = list(object({
    principal_id         = string
    role_definition_name = string
    description          = optional(string, null)
  }))
  default = []
} 