# Terragrunt configuration for Azure networking in eastus region

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

# Include the common configuration for Networking
include "networking_common" {
  path = find_in_parent_folders("azure/_envcommon/networking.hcl")
}

# Set dependencies for this module (these will merge with the common inputs)
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
    location = local.region
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  # Environment variables
  environment = local.env
  prefix = local.prefix
  region_abbv = local.region_abbv
  
  # Resource group
  resource_group_name = dependency.resource_group.outputs.name
  
  # Location
  location = dependency.resource_group.outputs.location
  
  # VNet configuration
  vnet_name = dependency.naming.outputs.virtual_network
  
  # Address space from network.hcl
  address_space = local.network_vars.locals.address_space
  
  # DNS configuration
  dns_servers = []
  
  # Subnets from network.hcl
  subnets = local.network_vars.locals.subnets
  
  # AKS Networking Configuration
  enable_aks_networking = true
  aks_subnet_name = "az1-kubernetes"
  aks_cluster_name = dependency.naming.outputs.aks_cluster
  aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"
} 