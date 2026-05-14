# Terragrunt configuration for Azure storage role assignments in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
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

# Add dependency on storage account
dependency "storage" {
  config_path = "../storage"

  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Storage/storageAccounts/mocksa"
    name = "stplatdeveus"
  }
}

# Define Terraform source
terraform {
  source = "${get_repo_root()}/infra/modules/azure//storage_roles"
}

# Specify inputs
inputs = {
  create = true

  # Storage account information - use the actual output from the storage module
  storage_account_id = dependency.storage.outputs.id

  # Role assignments
  role_assignments = [
    # Note: The Storage Blob Data Contributor role is already assigned by the storage module
    # It's duplicated here for state management purposes only
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
