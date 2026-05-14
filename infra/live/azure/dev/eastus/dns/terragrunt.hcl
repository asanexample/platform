# Terragrunt configuration for Azure Private DNS Zones in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

dependencies {
  paths = [
    "../resource_group",
    "../networking",
  ]
}

dependency "resource_group" {
  config_path = "../resource_group"

  mock_outputs = {
    name = "mock-rg"
  }
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure/private_dns"
}

inputs = {
  create = true

  resource_group_name = dependency.resource_group.outputs.name

  private_dns_zones = {
    blob = {
      name                      = "privatelink.blob.core.windows.net"
      vnet_id                   = dependency.networking.outputs.vnet_id
      vnet_resource_group_name  = dependency.resource_group.outputs.name
      registration_enabled      = false
      virtual_network_link_name = "${include.base.locals.workload}-blob-link"
    },
    file = {
      name                      = "privatelink.file.core.windows.net"
      vnet_id                   = dependency.networking.outputs.vnet_id
      vnet_resource_group_name  = dependency.resource_group.outputs.name
      registration_enabled      = false
      virtual_network_link_name = "${include.base.locals.workload}-file-link"
    },
    vault = {
      name                      = "privatelink.vaultcore.azure.net"
      vnet_id                   = dependency.networking.outputs.vnet_id
      vnet_resource_group_name  = dependency.resource_group.outputs.name
      registration_enabled      = false
      virtual_network_link_name = "${include.base.locals.workload}-vault-link"
    }
  }

  tags = include.base.locals.tags
}
