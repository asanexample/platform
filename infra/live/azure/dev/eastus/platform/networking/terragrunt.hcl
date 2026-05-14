# Terragrunt configuration for Azure networking in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

include "networking_common" {
  path = find_in_parent_folders("azure/_envcommon/networking.hcl")
}

dependency "naming" {
  config_path = "../naming"

  mock_outputs = {
    virtual_network = "mock-vnet"
    aks_cluster     = "mock-aks"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"

  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

inputs = {
  create = true

  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location

  vnet_name     = dependency.naming.outputs.virtual_network
  address_space = include.base.locals.network_vars.locals.address_space
  dns_servers   = []
  subnets       = include.base.locals.network_vars.locals.subnets

  enable_aks_networking   = true
  aks_subnet_name         = "az1-kubernetes"
  aks_cluster_name        = dependency.naming.outputs.aks_cluster
  aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"

  tags = merge(include.base.locals.tags, {
    "ResourceType" = "Networking"
  })
}
