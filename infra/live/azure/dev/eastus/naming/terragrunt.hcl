# Terragrunt configuration for Azure naming standards in eastus region

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
  env          = local.env_vars.locals.environment
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = local.region_vars.locals.region
  region_abbv  = local.region_vars.locals.region_abbv
  tags         = merge(
    local.common_vars.locals.tags, 
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the appropriate Terraform module as the source
terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${find_in_parent_folders("infra")}/modules/azure//naming"
}

# Specify inputs specific to this module
inputs = {
  # Naming components
  prefix      = local.prefix
  customer    = local.customer
  environment = local.env
  region_abbv = local.region_abbv
} 