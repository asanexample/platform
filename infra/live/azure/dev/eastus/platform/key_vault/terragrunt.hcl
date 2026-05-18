# Terragrunt configuration for Azure Key Vault in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "key_vault_common" {
  path = find_in_parent_folders("azure/_envcommon/key_vault.hcl")
}

# Module-specific locals
locals {
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }
}

dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    key_vault        = "mock-key-vault"
    private_endpoint = "mock-private-endpoint"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

dependency "networking" {
  config_path = "../networking"
  mock_outputs = {
    vnet_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    vnet_name = "mock-vnet"
    subnet_ids = {
      "az1-endpoints" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-endpoints"
    }
  }
}

inputs = {
  create = true

  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  location            = dependency.resource_group.outputs.location
  resource_group_name = dependency.resource_group.outputs.name
  name                = "${dependency.naming.outputs.key_vault}-1"

  enable_rbac_authorization  = true
  create_disk_encryption_key = true
  disk_encryption_key_name   = "disk-encryption-key"

  network_acls = local.network_acls

  private_endpoint = {
    name                = dependency.naming.outputs.private_endpoint
    resource_group_name = dependency.resource_group.outputs.name
    subnet_id           = dependency.networking.outputs.subnet_ids["az1-endpoints"]
    private_dns_zone_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
    private_service_connection = {
      name              = "kv-private-link"
      subresource_names = ["vault"]
    }
  }

  tags = include.base.locals.tags
}
