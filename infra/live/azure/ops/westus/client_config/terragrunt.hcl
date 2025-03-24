# Terragrunt configuration for Azure client config in eastus region

# Local variables for this configuration
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env    = local.env_vars.locals.environment
  region = local.region_vars.locals.region
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Define Terraform source
terraform {
  source = "${get_repo_root()}/infra/modules/azure//client_config"
}

# Specify inputs
inputs = {} 