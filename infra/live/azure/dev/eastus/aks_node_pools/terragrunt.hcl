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
  region_abbv  = "east"
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
  }
}

# Specify inputs specific to this module
inputs = {
  aks_cluster_id = dependency.aks_core.outputs.id
  environment    = local.env
  region_abbv    = local.region_abbv
  node_pools = {
    "app" = {
      vm_size             = "Standard_D4s_v3"
      enable_auto_scaling = true
      min_count           = 2
      max_count           = 5
      os_disk_size_gb     = 128
      os_disk_type        = "Managed"
      max_pods            = 30
      node_labels = {
        "nodepool-type" = "app"
        "environment"   = local.env
        "region"        = local.region
      }
    }
  }
}

