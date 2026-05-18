# Terragrunt configuration for Azure Resource Group in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "resource_group_common" {
  path = find_in_parent_folders("azure/_envcommon/resource_group.hcl")
}

dependency "naming" {
  config_path = "../naming"

  mock_outputs = {
    resource_group = "mock-rg"
  }
}

inputs = {
  create = true

  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  name = dependency.naming.outputs.resource_group
}
