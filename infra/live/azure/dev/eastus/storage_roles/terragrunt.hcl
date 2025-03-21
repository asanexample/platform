# Terragrunt configuration for Azure storage role assignments in eastus region

# Local variables for this configuration
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env         = local.env_vars.locals.environment
  region      = local.region_vars.locals.region
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Add data dependency for current client identity
dependency "client_config" {
  config_path = "../client_config"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    client_id       = "00000000-0000-0000-0000-000000000000"
    object_id       = "00000000-0000-0000-0000-000000000000"
    subscription_id = "00000000-0000-0000-0000-000000000000"
    tenant_id       = "00000000-0000-0000-0000-000000000000"
  }
}

# Define Terraform source
terraform {
  source = "${get_repo_root()}/infra/modules/azure//storage_roles"
}

# Specify inputs
inputs = {
  # Storage account information
  storage_account_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/vip-dev-rg-eus/providers/Microsoft.Storage/storageAccounts/vipdevsaeus"
  
  # Role assignments
  role_assignments = [
    {
      # Use the current user's object ID automatically
      principal_id         = dependency.client_config.outputs.object_id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant Storage Blob Data Contributor role to the current user"
    },
    {
      # Use the current user's object ID automatically for admin role
      principal_id         = dependency.client_config.outputs.object_id
      role_definition_name = "Storage Blob Data Owner"
      description          = "Grant Storage Blob Data Owner role to the current user"
    }
  ]
} 