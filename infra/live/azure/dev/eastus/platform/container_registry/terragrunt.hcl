# Terragrunt configuration for Azure Container Registry in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "acr_common" {
  path = find_in_parent_folders("azure/_envcommon/container_registry.hcl")
}

dependency "naming" {
  config_path = "../naming"

  mock_outputs = {
    container_registry = "mockacr"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"

  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

dependency "aks_core" {
  config_path = "../aks_core"

  mock_outputs = {
    kubelet_identity = {
      client_id                 = "00000000-0000-0000-0000-000000000000"
      object_id                 = "00000000-0000-0000-0000-000000000000"
      user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
    }
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure/container_registry"
}

inputs = {
  create = true

  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  name                          = dependency.naming.outputs.container_registry
  resource_group_name           = dependency.resource_group.outputs.name
  location                      = dependency.resource_group.outputs.location
  sku                           = "Standard"
  public_network_access_enabled = true

  aks_principal_id = dependency.aks_core.outputs.kubelet_identity.object_id

  tags = merge(include.base.locals.tags, {
    purpose     = "container-registry"
    application = "kubernetes-workloads"
    integration = "aks"
  })
}
