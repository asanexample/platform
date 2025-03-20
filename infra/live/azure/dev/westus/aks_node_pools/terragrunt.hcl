# Terragrunt configuration for Azure AKS Node Pools in westus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env         = local.common_vars.locals.env
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = "westus"
  region_abbv = "wus"
  tags        = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for AKS Node Pools
include "aks_node_pools_common" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/azure/aks_node_pools.hcl"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
  }
}

dependency "aks_core" {
  config_path = "../aks_core"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-aks"
    resource_group_name = "mock-rg"
    id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"
  mock_outputs = {
    id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  # AKS Reference
  aks_cluster_id = dependency.aks_core.outputs.id
  
  # Environment-specific node pool configuration
  app_node_pool = {
    enabled = true
    name = "apps"
    vm_size = "Standard_D4s_v4"
    node_count = 2
    # Removed availability zones since westus region doesn't support them
    availability_zones = []
    max_pods = 110
    os_disk_size_gb = 128
    os_disk_type = "Managed"
    enable_auto_scaling = true
    min_count = 2
    max_count = 5
    mode = "User"
    node_labels = {
      "nodepool" = "apps"
      "app" = "true"
      "workload" = "general"
      "node-priority" = "regular"
    }
    node_taints = []
  }
  
  # Required for updating certain node pool properties without recreation
  temporary_name_for_rotation = "tempapps"
  
  # Override standard node pool availability zones for westus region
  standard_node_pool = {
    availability_zones = []
  }
  
  # Tags
  tags = merge(local.tags, {
    "network-cilium-managed-by" = "cilium"
    "cilium-version" = "1.17.2"
  })
} 