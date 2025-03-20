# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR AKS NODE POOLS
# This is the common component configuration for AKS Node Pools. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Terraform module source for AKS Node Pools
terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${find_in_parent_folders("infra")}/modules/azure//aks_node_pools"
}

# ---------------------------------------------------------------------------------------------------------------------
# COMMON CONFIGURATION FOR AKS NODE POOLS
# These are the common configurations that should be the same across all environments
# ---------------------------------------------------------------------------------------------------------------------

# Default inputs for all environments
inputs = {
  # Common standard node pool configuration
  standard_node_pool = {
    name                = "standard"
    vm_size             = "Standard_D4s_v3"
    enable_auto_scaling = true
    node_count          = 2
    min_count           = 2
    max_count           = 10
    availability_zones  = ["1", "2", "3"]
    node_labels = {
      "nodepool-type" = "standard"
      "environment"   = "standard"
      "nodepoolos"    = "linux"
    }
    node_taints         = []
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"
    os_sku              = "Ubuntu"
    ultra_ssd_enabled   = false
    max_pods            = 110
  }
  
  # Common performance node pool configuration
  performance_node_pool = {
    name                = "perf"
    vm_size             = "Standard_D8s_v3"
    enable_auto_scaling = true
    node_count          = 0
    min_count           = 0
    max_count           = 5
    availability_zones  = ["1", "2", "3"]
    node_labels = {
      "nodepool-type" = "performance"
      "environment"   = "performance"
      "nodepoolos"    = "linux"
      "highcpu"       = "true"
    }
    node_taints         = ["workloadtype=performance:NoSchedule"]
    os_disk_size_gb     = 256
    os_disk_type        = "Managed"
    os_sku              = "Ubuntu"
    ultra_ssd_enabled   = true
    max_pods            = 110
  }
  
  # Common spot node pool configuration
  spot_node_pool = {
    name                = "spot"
    vm_size             = "Standard_D4s_v3"
    enable_auto_scaling = true
    node_count          = 0
    min_count           = 0
    max_count           = 10
    availability_zones  = ["1", "2", "3"]
    node_labels = {
      "nodepool-type" = "spot"
      "environment"   = "spot"
      "nodepoolos"    = "linux"
    }
    node_taints         = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"
    os_sku              = "Ubuntu"
    ultra_ssd_enabled   = false
    max_pods            = 110
    spot_enabled        = true
    spot_max_price      = -1 # Default to current on-demand price
    eviction_policy     = "Delete"
  }
  
  # Common settings for all node pools
  common_node_pool_settings = {
    workload_runtime      = "OCIContainer"
    enable_host_encryption = false
    enable_node_public_ip = false
    orchestrator_version  = null # Will use the same version as the cluster
    proximity_placement_group_id = null
  }
} 