# Terragrunt configuration for Azure Front Door Profile in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

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

terraform {
  source = "${get_repo_root()}/infra/modules/azure/frontdoor_profile"
}

inputs = {
  create                   = true
  name                     = dependency.naming.outputs.frontdoor_profile
  resource_group_name      = dependency.resource_group.outputs.name
  sku_name                 = "Premium_AzureFrontDoor"
  response_timeout_seconds = 60

  tags = include.base.locals.tags
}
