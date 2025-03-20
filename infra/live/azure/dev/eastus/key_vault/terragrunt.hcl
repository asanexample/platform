# Terragrunt configuration for Azure key_vault in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "east"
  tags         = local.common_vars.locals.tags
  
  # Generate a truly unique random suffix for key vault name (include timestamp for uniqueness)
  timestamp = formatdate("YYMMDDHHmmss", timestamp())
  random_suffix = substr(md5("${local.region}-${local.timestamp}"), 0, 6)
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the key_vault module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/key_vault"
}
# Set dependencies for this module
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
  }
}

dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    key_vault = "mock-kv"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  key_vault_name      = "${dependency.naming.outputs.key_vault}-${local.random_suffix}"
  tags                = local.tags
}

