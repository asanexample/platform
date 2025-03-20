# Terragrunt configuration for Azure Resource Group in westus region

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
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for Resource Groups
include "resource_group_common" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/azure/resource_group.hcl"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = "mock-rg"
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  name = dependency.naming.outputs.resource_group
} 