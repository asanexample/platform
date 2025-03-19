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

# Use the AKS node pools module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/aks_node_pools"
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
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"
  mock_outputs = {
    id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
}


# Specify inputs specific to this module
inputs = {
  # Naming
  prefix      = local.prefix
  customer    = local.customer
  stage       = local.env
  region_abbv = local.region_abbv
  
  # AKS Reference
  aks_cluster_id = dependency.aks_core.outputs.id
  
  # App Node Pool Configuration
  app_node_pool_enabled = true
  app_node_pool_name = "apps"
  app_node_pool_vm_size = "Standard_D4s_v4"
  app_node_pool_node_count = 2
  # Removed availability zones since westus region doesn't support them
  app_node_pool_availability_zones = []
  
  # Set max_pods to a higher value since Cilium doesn't use the Azure CNI per-node IP allocation
  # Cilium can support more pods per node as it uses its own IPAM
  app_node_pool_max_pods = 110
  
  # Required for updating certain node pool properties without recreation
  temporary_name_for_rotation = "tempapps"
  
  app_node_pool_os_disk_size_gb = 128
  app_node_pool_os_disk_type = "Managed"
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count = 2
  app_node_pool_max_count = 5
  app_node_pool_mode = "User"
  app_node_pool_node_labels = {
    "nodepool" = "apps"
    "app" = "true"
    "workload" = "general"
    "node-priority" = "regular"
  }
  
  # No taints by default for the app node pool
  app_node_pool_node_taints = []
  
  # Tags
  tags = merge(local.tags, {
    "network-cilium-managed-by" = "cilium"
    "cilium-version" = "1.14.2"
  })
} 