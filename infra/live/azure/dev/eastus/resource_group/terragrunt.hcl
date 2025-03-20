# Terragrunt configuration for Azure resource_group in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "eus"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the resource_group module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/resource_group"
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
  name     = dependency.naming.outputs.resource_group
  location = local.region
  tags     = local.tags
}

