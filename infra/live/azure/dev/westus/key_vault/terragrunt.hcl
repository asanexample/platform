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
  source = "${get_repo_root()}/infra/modules/azure/key_vault"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    key_vault          = "mock-key-vault"
    private_endpoint   = "mock-private-endpoint"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    name = "mock-rg"
    location = "westus"
  }
}

dependency "network" {
  config_path = "../networking"
  mock_outputs = {
    vnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    vnet_name                = "mock-vnet"
    subnet_ids               = { "az1-endpoints" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-endpoints" }
  }
}

# Specify inputs specific to this module
inputs = {
  location            = "westus"
  resource_group_name = dependency.resource_group.outputs.name
  
  # Use a fixed unique name that doesn't change on every apply
  name = "vipdevwuskv${local.unique_suffix}"
  
  # The line below was the previous naming approach using timestamp which caused recreation issues
  # name = "vipdeveuskv${local.timestamp_suffix}"

  # Enable RBAC authorization
  enable_rbac_authorization = true

  # Create a disk encryption key
  create_disk_encryption_key = true
  disk_encryption_key_name = "disk-encryption-key"

  # Network rules
  network_acls = local.network_acls

  # Configure private endpoint
  private_endpoint = {
    name                = dependency.naming.outputs.private_endpoint
    resource_group_name = dependency.resource_group.outputs.name
    subnet_id           = dependency.network.outputs.subnet_ids["az1-endpoints"]
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