# Terragrunt configuration for Azure hosting in eastus region

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Include common config for hosting
include "common" {
  path   = "${dirname(find_in_parent_folders())}/live/azure/_envcommon/hosting.hcl"
  expose = true
}

# Include region-specific network configuration
locals {
  # Read network configuration from network.hcl in the region directory
  network_config = read_terragrunt_config(find_in_parent_folders("network.hcl"))
}

# Inputs that are the same for all regions
inputs = {
  # Forward network configuration from network.hcl
  address_space = local.network_config.locals.address_space
  subnets       = local.network_config.locals.subnets
} 