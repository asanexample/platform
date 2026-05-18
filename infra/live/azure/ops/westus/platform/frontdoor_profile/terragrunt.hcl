# Terragrunt configuration for Azure Front Door Profile in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root configuration (root.hcl)
include "root" {
  path = find_in_parent_folders("root.hcl")
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
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

# Define terraform source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/frontdoor_profile"
}

# Specify inputs specific to this module
inputs = {
  # Control deployment
  create = false

  # Resource details
  name                = dependency.naming.outputs.frontdoor_profile
  resource_group_name = dependency.resource_group.outputs.name

  # Front Door settings
  sku_name                 = "Premium_AzureFrontDoor" # Using Premium SKU for production
  response_timeout_seconds = 120

  # Tags
  tags = include.base.locals.tags
}
