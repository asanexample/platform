# Terragrunt configuration for Azure Resource Group in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for Resource Group
include "resource_group_common" {
  path = find_in_parent_folders("azure/_envcommon/resource_group.hcl")
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"

  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = "mock-rg"
  }
}

# Specify inputs specific to this module
inputs = {
  create = true

  # Environment variables
  environment = include.base.locals.env
  workload = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  name = dependency.naming.outputs.resource_group
}
