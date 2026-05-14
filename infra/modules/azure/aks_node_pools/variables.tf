/**
 * Variables for the AKS Node Pools module
 *
 * This module focuses on creating node pools for an existing AKS cluster
 */

variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

# Naming module variables
variable "workload" {
  description = "Workload identifier for resource names"
  type        = string
  default     = "platform"
  validation {
    condition     = length(var.workload) >= 3 && length(var.workload) <= 10
    error_message = "The workload must be between 3 and 10 characters."
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
  description = "The abbreviated Azure region name (e.g., wus, eus, neu)."
  type        = string
  validation {
    condition     = length(var.region_abbv) >= 2 && length(var.region_abbv) <= 5
    error_message = "Region abbreviation should be between 2 and 5 characters."
  }
  validation {
    condition     = can(regex("^[a-z]+$", var.region_abbv))
    error_message = "Region abbreviation should only contain lowercase letters."
  }
}

# AKS Cluster Reference
variable "aks_cluster_id" {
  description = "The ID of the AKS cluster where node pools will be created"
  type        = string
  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerService/managedClusters/[^/]+$", var.aks_cluster_id))
    error_message = "The AKS cluster ID must be a valid Azure resource ID for a managed Kubernetes cluster."
  }
}

# App Node Pool Configuration
variable "app_node_pool_enabled" {
  description = "Enable application node pool"
  type        = bool
  default     = true
  validation {
    condition     = var.app_node_pool_enabled != null
    error_message = "The app_node_pool_enabled value must be either true or false."
  }
}

variable "use_availability_zones" {
  description = "Controls whether to use availability zones for node pools. Set to false for regions that don't support zones for VMSS."
  type        = bool
  default     = null
}

variable "app_node_pool_name" {
  description = "Name of the application node pool"
  type        = string
  default     = "apps"

  validation {
    condition     = var.app_node_pool_name == null ? true : length(var.app_node_pool_name) >= 1 && length(var.app_node_pool_name) <= 12
    error_message = "Application node pool name must be between 1 and 12 characters."
  }

  validation {
    condition     = var.app_node_pool_name == null ? true : can(regex("^[a-z][a-z0-9]*$", var.app_node_pool_name))
    error_message = "Application node pool name can only include lowercase alphanumeric characters and must start with a letter."
  }
}

variable "app_node_pool_vm_size" {
  description = "VM size for the application node pool"
  type        = string
  default     = "Standard_D4s_v4"
  validation {
    condition     = length(var.app_node_pool_vm_size) > 0
    error_message = "The VM size must not be empty."
  }
  validation {
    condition     = can(regex("^Standard_", var.app_node_pool_vm_size))
    error_message = "The VM size must start with 'Standard_'."
  }
}

variable "app_node_pool_node_count" {
  description = "Initial number of nodes in the application node pool"
  type        = number
  default     = 2

  validation {
    condition     = var.app_node_pool_node_count >= 0 && var.app_node_pool_node_count <= 1000
    error_message = "Application node pool count must be between 0 and 1000."
  }
}

variable "app_node_pool_availability_zones" {
  description = "Availability zones for the application node pool"
  type        = list(string)
  default     = ["1", "2", "3"]
  validation {
    condition = alltrue([
      for zone in var.app_node_pool_availability_zones : contains(["1", "2", "3"], zone)
    ]) || length(var.app_node_pool_availability_zones) == 0
    error_message = "Availability zones must be one or more of: 1, 2, 3."
  }
}

variable "app_node_pool_max_pods" {
  description = "The maximum number of pods per node for the app node pool"
  type        = number
  default     = 110  # Higher value for Cilium CNI (not constrained by Azure CNI limits)
  validation {
    condition     = var.app_node_pool_max_pods >= 30 && var.app_node_pool_max_pods <= 250
    error_message = "The app node pool maximum pods must be between 30 and 250."
  }
}

variable "app_node_pool_os_disk_size_gb" {
  description = "OS disk size for nodes in the application node pool"
  type        = number
  default     = 128

  validation {
    condition     = var.app_node_pool_os_disk_size_gb >= 30 && var.app_node_pool_os_disk_size_gb <= 2048
    error_message = "OS disk size must be between 30 and 2048 GB."
  }
}

variable "app_node_pool_os_disk_type" {
  description = "OS disk type for nodes in the application node pool"
  type        = string
  default     = "Managed"

  validation {
    condition     = contains(["Managed", "Ephemeral"], var.app_node_pool_os_disk_type)
    error_message = "OS disk type must be either 'Managed' or 'Ephemeral'."
  }
}

variable "app_node_pool_enable_auto_scaling" {
  description = "Enable auto-scaling for the application node pool"
  type        = bool
  default     = true
  validation {
    condition     = var.app_node_pool_enable_auto_scaling != null
    error_message = "The app_node_pool_enable_auto_scaling value must be either true or false."
  }
}

variable "app_node_pool_min_count" {
  description = "Minimum node count for auto-scaling"
  type        = number
  default     = 1

  validation {
    condition     = var.app_node_pool_min_count >= 0 && var.app_node_pool_min_count <= 1000
    error_message = "Minimum node count must be between 0 and 1000."
  }
}

variable "app_node_pool_max_count" {
  description = "Maximum node count for auto-scaling"
  type        = number
  default     = 5

  validation {
    condition     = var.app_node_pool_max_count >= 0 && var.app_node_pool_max_count <= 1000
    error_message = "Maximum node count must be between 0 and 1000."
  }
  validation {
    condition     = var.app_node_pool_max_count >= var.app_node_pool_min_count
    error_message = "Maximum node count must be greater than or equal to minimum node count."
  }
}

variable "app_node_pool_mode" {
  description = "Mode for the application node pool (System or User)"
  type        = string
  default     = "User"

  validation {
    condition     = contains(["System", "User"], var.app_node_pool_mode)
    error_message = "Node pool mode must be either 'System' or 'User'."
  }
}

variable "app_node_pool_node_labels" {
  description = "Labels to apply to nodes in the application node pool"
  type        = map(string)
  default = {
    "nodepool" = "apps"
    "app"      = "true"
  }
  validation {
    condition = alltrue([
      for key in keys(var.app_node_pool_node_labels) : length(key) >= 1 && length(key) <= 63
    ]) || length(var.app_node_pool_node_labels) == 0
    error_message = "Node label keys must be between 1 and 63 characters."
  }
  validation {
    condition = alltrue([
      for value in values(var.app_node_pool_node_labels) : length(value) >= 1 && length(value) <= 63
    ]) || length(var.app_node_pool_node_labels) == 0
    error_message = "Node label values must be between 1 and 63 characters."
  }
}

variable "app_node_pool_node_taints" {
  description = "A list of Kubernetes taints which should be applied to nodes in the application node pool"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for taint in var.app_node_pool_node_taints : can(regex("^[a-zA-Z0-9-_.]+=[a-zA-Z0-9-_.]+:(NoSchedule|PreferNoSchedule|NoExecute)$", taint))
    ]) || length(var.app_node_pool_node_taints) == 0
    error_message = "Node taints must be in the format 'key=value:effect' where effect is one of NoSchedule, PreferNoSchedule, or NoExecute."
  }
}

variable "temporary_name_for_rotation" {
  description = "Specifies the name of the temporary node pool used to cycle the node pool for updates"
  type        = string
  default     = null
  validation {
    condition     = var.temporary_name_for_rotation == null ? true : length(var.temporary_name_for_rotation) >= 1 && length(var.temporary_name_for_rotation) <= 12
    error_message = "Temporary node pool name must be between 1 and 12 characters when provided."
  }
  validation {
    condition     = var.temporary_name_for_rotation == null ? true : can(regex("^[a-z][a-z0-9]*$", var.temporary_name_for_rotation))
    error_message = "Temporary node pool name can only include lowercase alphanumeric characters and must start with a letter."
  }
}

# Tagging
variable "tags" {
  description = "Tags to apply to the node pools"
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