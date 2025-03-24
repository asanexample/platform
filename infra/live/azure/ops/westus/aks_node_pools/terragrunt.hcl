# Terragrunt configuration for Azure AKS Node Pools in eastus region

# Local variables for this configuration
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Merge all variables for convenience
  all_vars = merge(
    local.env_vars.locals,
    local.region_vars.locals,
    local.network_vars.locals,
    local.common_vars.locals
  )
  
  # Extract commonly used variables
  env         = local.env_vars.locals.environment
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  tags        = merge(
    local.common_vars.locals.tags, 
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for AKS Node Pools
include "aks_node_pools_common" {
  path = find_in_parent_folders("azure/_envcommon/aks_node_pools.hcl")
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
  # Required variables that were missing
  environment = local.env
  region_abbv = local.region_abbv
  
  # AKS Reference
  aks_cluster_id = dependency.aks_core.outputs.id
  
  # Disable availability zones for westus region as it doesn't support zones for VMSS
  use_availability_zones = false
  
  # Environment-specific node pool configuration
  app_node_pool = {
    enabled = true
    name = "apps"
    vm_size = "Standard_D8s_v5"
    node_count = 3
    # Use availability zones for high availability
    availability_zones = ["1", "2", "3"]
    max_pods = 110
    os_disk_size_gb = 128
    os_disk_type = "Managed"
    enable_auto_scaling = true
    min_count = 3
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
  
  # Direct variable for min_count to ensure it's properly set
  app_node_pool_min_count = 3
  
  # Required for updating certain node pool properties without recreation
  temporary_name_for_rotation = "tempapps"
  
  # Override standard node pool availability zones for this region
  standard_node_pool = {
    availability_zones = ["1", "2", "3"]
    node_count = 3
    min_count = 3
  }
  
  # Tags
  tags = merge(local.tags, {
    "network-cilium-managed-by" = "cilium"
    "cilium-version" = "1.17.2"
  })
} 