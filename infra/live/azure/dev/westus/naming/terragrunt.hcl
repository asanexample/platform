# Terragrunt configuration for Azure naming standards in westus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "westus"
  region_abbv  = "wus"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the actual Terraform module as the source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/naming"
}

# Specify inputs specific to this module
inputs = {
  # Naming components
  prefix      = local.prefix
  customer    = local.customer
  environment = local.env
  region_abbv = local.region_abbv
} 