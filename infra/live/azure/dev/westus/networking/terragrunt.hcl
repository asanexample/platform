# Terragrunt configuration for Azure networking in westus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Load network configuration
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  
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

# Include the common configuration for Networking
include "networking_common" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/azure/networking.hcl"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    virtual_network = "mock-vnet"
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

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  # Resource group
  resource_group_name = dependency.resource_group.outputs.name
  
  # VNet configuration
  vnet_name = dependency.naming.outputs.virtual_network
  
  # Subnets from network.hcl
  subnets = local.network_vars.locals.subnets
  
  # AKS Networking Configuration
  enable_aks_networking = true
  aks_subnet_name = "az1-kubernetes"
  aks_cluster_name = dependency.naming.outputs.aks_cluster
  aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"
} 