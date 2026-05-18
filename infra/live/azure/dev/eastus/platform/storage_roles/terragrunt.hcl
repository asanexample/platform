# Terragrunt configuration for Azure storage role assignments in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "client_config" {
  config_path = "../client_config"

  mock_outputs = {
    client_id       = "00000000-0000-0000-0000-000000000000"
    object_id       = "00000000-0000-0000-0000-000000000000"
    subscription_id = "00000000-0000-0000-0000-000000000000"
    tenant_id       = "00000000-0000-0000-0000-000000000000"
  }
}

dependency "storage" {
  config_path = "../storage"

  mock_outputs = {
    id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Storage/storageAccounts/mocksa"
    name = "stplatdeveus"
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure//storage_roles"
}

inputs = {
  create = true

  storage_account_id = dependency.storage.outputs.id

  role_assignments = [
    {
      principal_id         = dependency.client_config.outputs.object_id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant Storage Blob Data Contributor role to the current user"
    },
    {
      principal_id         = dependency.client_config.outputs.object_id
      role_definition_name = "Storage Blob Data Owner"
      description          = "Grant Storage Blob Data Owner role to the current user"
    }
  ]
}
