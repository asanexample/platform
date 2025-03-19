# Terragrunt configuration for Azure Key Vault in westus region

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
  
  # Resource Group
  resource_group_name = "vip-dev-wus-rg"
  
  # Use a fixed unique suffix instead of timestamp
  unique_suffix = "01"
  
  # Network rules
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }
  
  # The value below is no longer needed as we're using a fixed name
  # timestamp_suffix = replace(substr(timestamp(), 0, 16), "-", "")
  # timestamp_suffix = replace(replace(substr(timestamp(), 0, 16), "-", ""), ":", "")
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the actual Terraform module as the source
terraform {
  source = "${get_parent_terragrunt_dir()}/../../../modules/azure/key_vault"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    key_vault          = "mock-key-vault"
    key_vault_key      = "mock-key-vault-key"
    private_dns_zone   = "mock-dns-zone"
    private_endpoint   = "mock-private-endpoint"
    disk_encryption_set = "mock-disk-encryption-set"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    resource_group_name = local.resource_group_name
  }
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    vnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    vnet_name                = "mock-vnet"
    subnet_ids               = { private_endpoints = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/private-endpoints" }
    vnet_subnet_ids          = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/private-endpoints"]
    private_endpoints_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/private-endpoints"
  }
}

# Specify inputs specific to this module
inputs = {
  location            = "westus"
  resource_group_name = dependency.resource_group.outputs.resource_group_name
  
  # Use a fixed unique name that doesn't change on every apply
  name = "vipdevwuskv${local.unique_suffix}"
  
  # The line below was the previous naming approach using timestamp which caused recreation issues
  # name = "vipdeveuskv${local.timestamp_suffix}"

  # Enable RBAC authorization
  enable_rbac_authorization = true

  # Create a disk encryption key
  create_disk_encryption_key = true
  disk_encryption_key_name = dependency.naming.outputs.key_vault_key

  # Network rules
  network_acls = local.network_acls

  # Configure private endpoint
  private_endpoint = {
    name                = dependency.naming.outputs.private_endpoint
    resource_group_name = dependency.resource_group.outputs.resource_group_name
    subnet_id           = dependency.network.outputs.private_endpoints_subnet_id
    private_dns_zone_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
    private_service_connection = {
      name = "kv-private-link"
      subresource_names = ["vault"]
    }
  }

  # Tags
  tags = {
    environment = "dev"
    application = "VIP Platform"
  }
} 