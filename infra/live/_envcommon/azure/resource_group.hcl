# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR AZURE RESOURCE GROUPS
# This is the common component configuration for Azure Resource Groups. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Terraform module source for resource groups
terraform {
  source = "${dirname(find_in_parent_folders())}/modules/azure/resource_group"
}

# ---------------------------------------------------------------------------------------------------------------------
# SHARED VARIABLES
# These variables are used across all environments and regions
# ---------------------------------------------------------------------------------------------------------------------
locals {
  # Extract environment from env.hcl
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  
  # Extract region information from region.hcl
  region_vars    = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region         = local.region_vars.locals.region
  
  # Get common tags from the environment
  common_vars    = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  common_tags    = local.common_vars.locals.tags
}

# Default inputs that typically won't need to be overridden in specific environments
inputs = {
  # The name will typically come from the naming module in environment-specific configs
  location = local.region
  
  # Default tags that should be applied to all resource groups
  tags = merge(local.common_tags, {
    "ResourceType" = "ResourceGroup"
  })
} 