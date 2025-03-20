# Terragrunt configuration for Azure Private DNS Zones

# Local variables for this configuration
locals {
  # Load env, region, and common configuration
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))

  # Merge all variables for convenience
  merged = merge(
    local.env_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals,
  )

  # Extract commonly used variables
  env      = local.merged.env
  prefix   = local.merged.prefix
  region   = local.merged.region
  tags     = local.merged.tags
}

# Include the root terragrunt.hcl configuration
include {
  path = find_in_parent_folders()
}

# Define dependencies
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

# Set the source to our custom module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/private_dns"
}

inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  
  private_dns_zones = {
    blob = {
      name                      = "privatelink.blob.core.windows.net"
      vnet_id                   = dependency.networking.outputs.vnet_id
      vnet_resource_group_name  = dependency.resource_group.outputs.name
      registration_enabled      = false
      virtual_network_link_name = "${local.prefix}-blob-link"
    },
    file = {
      name                      = "privatelink.file.core.windows.net"
      vnet_id                   = dependency.networking.outputs.vnet_id
      vnet_resource_group_name  = dependency.resource_group.outputs.name
      registration_enabled      = false
      virtual_network_link_name = "${local.prefix}-file-link"
    },
    vault = {
      name                      = "privatelink.vaultcore.azure.net"
      vnet_id                   = dependency.networking.outputs.vnet_id
      vnet_resource_group_name  = dependency.resource_group.outputs.name
      registration_enabled      = false
      virtual_network_link_name = "${local.prefix}-vault-link"
    }
  }
  
  tags = local.tags
} 