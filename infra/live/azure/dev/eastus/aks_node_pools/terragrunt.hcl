# Terragrunt configuration for Azure aks_node_pools in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "eus"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the aks_node_pools module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/aks_node_pools"
}
# Set dependencies for this module
dependency "aks_core" {
  config_path = "../aks_core"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
    name = "mock-aks"
  }
}

# Add dependency for resource group
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
  }
}

# Add dependency for networking
dependency "networking" {
  config_path = "../networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    subnet_ids = {
      "az2-kubernetes" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az2-kubernetes"
    }
  }
}

# Specify inputs specific to this module
inputs = {
  prefix       = local.prefix
  customer     = local.customer
  environment  = local.env
  region_abbv  = local.region_abbv
  
  # Use the actual ID from the AKS cluster output
  aks_cluster_id = dependency.aks_core.outputs.id
  
  app_node_pool_enabled = true
  app_node_pool_vm_size = "Standard_D4s_v3"
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count = 2
  app_node_pool_max_count = 5
  app_node_pool_os_disk_size_gb = 128
  app_node_pool_os_disk_type = "Managed"
  app_node_pool_max_pods = 30
  app_node_pool_node_labels = {
    "nodepool-type" = "app"
    "environment" = local.env
    "region" = local.region
  }
  
  app_node_pool_vnet_subnet_id = dependency.networking.outputs.subnet_ids["az2-kubernetes"]
  
  tags = local.tags
}

