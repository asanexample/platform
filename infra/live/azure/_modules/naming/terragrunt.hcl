# Terragrunt configuration for the naming module

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Configure the module source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/naming"
}

# Default inputs for the naming module (can be overridden by environments)
inputs = {
  prefix      = "vip"
  customer    = null    # Default to no customer (shared infrastructure)
  stage       = "dev"   # Default to dev environment
  region_abbv = "eus"   # Default to eastus region
} 