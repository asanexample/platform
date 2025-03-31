# Terragrunt configuration for Azure Front Door Profile in eastus region

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
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    frontdoor_profile = "mock-fd"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    name = "mock-rg"
    location = local.region
  }
}

# Define terraform source
terraform {
  source = "${get_path_to_repo_root()}/infra/modules/azure/frontdoor_profile"
}

# Specify inputs specific to this module
inputs = {
  # Resource details
  name                = dependency.naming.outputs.frontdoor_profile
  resource_group_name = dependency.resource_group.outputs.name
  
  # Front Door settings
  sku_name = "Premium_AzureFrontDoor"
  response_timeout_seconds = 60
  
  # Tags
  tags = local.tags
} 