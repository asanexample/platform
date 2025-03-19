# ⚠️ DEPRECATED - This module has been deprecated ⚠️
# 
# The AKS networking functionality has been consolidated into the main networking module.
# Please use the networking module with AKS-specific parameters instead:
#
# Example:
# ```hcl
# # In networking/terragrunt.hcl
# inputs = {
#   # Regular networking parameters...
#
#   # AKS Networking Configuration
#   enable_aks_networking = true
#   aks_subnet_name = "az1-node-subnet"
#   aks_cluster_name = dependency.naming.outputs.aks_cluster
#   aks_private_cluster_enabled = true
#   aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"
# }
# ```
#
# This file is kept for reference only and should not be used.

# Terragrunt configuration for Azure AKS Networking in westus region

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

# Use the AKS networking module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/aks_networking"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
    location = "westus"
  }
}

dependency "networking" {
  config_path = "../networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    subnet_ids = {
      "az1-node-subnet" = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-node-subnet"
    }
  }
}

# Skip this module during apply/plan since it's deprecated
skip = true

# Specify inputs specific to this module - kept for reference
inputs = {
  # Naming
  prefix      = local.prefix
  customer    = local.customer
  stage       = local.env
  region_abbv = local.region_abbv
  
  # Resource details
  resource_group_name = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location
  
  # AKS configuration
  cluster_name = dependency.naming.outputs.aks_cluster
  node_resource_group = "${dependency.resource_group.outputs.name}-nodes"
  
  # Network configuration
  subnet_id = dependency.networking.outputs.subnet_ids["az1-node-subnet"]
  private_cluster_enabled = true
  
  # Tags
  tags = local.tags
} 