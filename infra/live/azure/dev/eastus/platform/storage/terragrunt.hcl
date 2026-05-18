# Terragrunt configuration for Azure storage in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "storage_common" {
  path = find_in_parent_folders("azure/_envcommon/storage.hcl")
}

dependency "client_config" {
  config_path = "../client_config"

  mock_outputs = {
    client_id       = "00000000-0000-0000-0000-000000000000"
    object_id       = "00000000-0000-0000-0000-000000000000"
    subscription_id = "00000000-0000-0000-0000-000000000000"
    tenant_id       = "00000000-0000-0000-0000-000000000000"
  }
}

dependency "naming" {
  config_path = "../naming"

  mock_outputs = {
    storage_account  = "mocksa"
    private_endpoint = "mock-pe"
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
    subnet_ids = {
      "az1-endpoints" = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-endpoints"
    }
  }
}

dependency "dns" {
  config_path = "../dns"

  mock_outputs = {
    private_dns_zone_ids = {
      "blob" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    }
  }
}

inputs = {
  create = true

  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  name                = dependency.naming.outputs.storage_account

  account_tier             = "Standard"
  account_replication_type = "LRS"

  public_network_access_enabled = true

  network_rules = {
    default_action = "Allow"
    bypass         = ["AzureServices"]
    virtual_network_subnet_ids = [
      dependency.networking.outputs.subnet_ids["az1-endpoints"]
    ]
  }

  private_endpoint = {
    create                         = true
    name                           = dependency.naming.outputs.private_endpoint
    subnet_id                      = dependency.networking.outputs.subnet_ids["az1-endpoints"]
    subresource_names              = ["blob"]
    private_service_connection_name = "service-connection"
    private_dns_zone_ids           = [dependency.dns.outputs.private_dns_zone_ids["blob"]]
  }

  containers = {
    "data" = { name = "data", container_access_type = "private" }
    "logs" = { name = "logs", container_access_type = "private" }
  }

  lifecycle_rules = [
    {
      name         = "logs-lifecycle"
      enabled      = true
      prefix_match = ["logs/"]
      tier_to_cool_action    = { days_after_modification_greater_than = 30 }
      tier_to_archive_action = { days_after_modification_greater_than = 90 }
      delete_action          = { days_after_modification_greater_than = 730 }
    }
  ]

  allow_nested_items_to_be_public = false
  blob_public_access_enabled      = false
  shared_access_key_enabled       = true

  tags = include.base.locals.tags
}
