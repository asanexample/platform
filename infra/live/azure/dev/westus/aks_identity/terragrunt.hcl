# Terragrunt configuration for Azure AKS Identity in westus region

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

# Use the AKS identity module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/aks_identity"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
    user_assigned_identity = "mock-identity"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
    location = "westus"
  }
}

# Specify inputs specific to this module
inputs = {
  # Naming
  prefix      = local.prefix
  customer    = local.customer
  stage       = local.env
  region_abbv = local.region_abbv
  aks_identity_name = dependency.naming.outputs.user_assigned_identity
  
  # Resource details
  resource_group_name = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location
  
  # Configuration
  create_workload_identities = false
  workload_identity_enabled = false
  oidc_issuer_enabled = false
  
  # Tags
  tags = local.tags
} 