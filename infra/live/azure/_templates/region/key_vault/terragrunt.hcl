# Terragrunt configuration for Azure Key Vault in ${region} region

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
  
  # Network rules
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for Key Vault
include "key_vault_common" {
  path = find_in_parent_folders("azure/_envcommon/key_vault.hcl")
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
    location = local.region
  }
}

dependency "networking" {
  config_path = "../networking"
  mock_outputs = {
    vnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    vnet_name                = "mock-vnet"
    subnet_ids               = { "az1-endpoints" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-endpoints" }
  }
}

# Specify inputs specific to this module
inputs = {
  # Environment variables
  environment = local.env
  customer = local.customer
  prefix = local.prefix
  region_abbv = local.region_abbv
  
  # Resource details
  location            = dependency.resource_group.outputs.location
  resource_group_name = dependency.resource_group.outputs.name
  
  # Key vault name from naming module
  name = dependency.naming.outputs.key_vault

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
    subnet_id           = dependency.networking.outputs.subnet_ids["az1-endpoints"]
    private_dns_zone_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    ]
    private_service_connection = {
      name = "kv-private-link"
      subresource_names = ["vault"]
    }
  }
  
  # Tags
  tags = local.tags
} 