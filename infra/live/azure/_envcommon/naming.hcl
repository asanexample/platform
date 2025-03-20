# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR RESOURCE NAMING
# This file defines the configuration for the Azure naming module that standardizes resource naming
# across all environments and regions.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${find_in_parent_folders("infra")}/modules/azure//naming"
}

# ---------------------------------------------------------------------------------------------------------------------
# SHARED LOCALS FROM PARENT FILES
# These locals are automatically pulled from environment and region configuration files.
# ---------------------------------------------------------------------------------------------------------------------
locals {
  # Extract environment from env.hcl
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  
  # Extract region information from region.hcl
  region_vars    = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region         = local.region_vars.locals.region
  region_abbv    = local.region_vars.locals.region_abbv
  
  # Get common tags from the environment
  common_vars    = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  prefix         = local.common_vars.locals.prefix
  
  # Try to get customer information if available
  customer       = try(local.common_vars.locals.customer, "")
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we need to pass to the module to build standardized resource names.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  prefix      = local.prefix
  customer    = local.customer
  environment = local.environment
  region_abbv = local.region_abbv
} 