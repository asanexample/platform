# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR RESOURCE NAMING
# This is the common component configuration for resource naming. The common parameters defined in this file will be
# used across all environments to ensure consistent resource naming following Azure best practices.
# ---------------------------------------------------------------------------------------------------------------------

# Terraform module source for Azure Naming 
terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${get_repo_root()}/infra/modules/azure//naming"
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
  workload       = local.common_vars.locals.workload
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we need to pass to the module to build standardized resource names.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  workload    = local.workload
  environment = local.environment
  region_abbv = local.region_abbv
} 