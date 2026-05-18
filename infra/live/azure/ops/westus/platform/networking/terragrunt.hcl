# Terragrunt configuration for Azure networking in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root configuration (root.hcl)
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include the common configuration for Networking
include "networking_common" {
  path = find_in_parent_folders("azure/_envcommon/networking.hcl")
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
    location = include.base.locals.region
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  create = true

  # Environment variables
  environment = include.base.locals.env
  workload = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  # Resource group
  resource_group_name = dependency.resource_group.outputs.name

  # Location
  location = dependency.resource_group.outputs.location

  # VNet configuration
  vnet_name = dependency.naming.outputs.virtual_network

  # Address space from network.hcl
  address_space = include.base.locals.network_vars.locals.address_space

  # DNS configuration
  dns_servers = []

  # Subnets from network.hcl
  subnets = include.base.locals.network_vars.locals.subnets

  # AKS Networking Configuration
  enable_aks_networking = true
  aks_subnet_name = "az1-kubernetes"
  aks_cluster_name = dependency.naming.outputs.aks_cluster
  aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"

  tags = merge(include.base.locals.tags, {
    "ResourceType" = "Networking"
  })
}
