# Terragrunt configuration for Azure Container Registry in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include common configuration for Container Registry
include "acr_common" {
  path = find_in_parent_folders("azure/_envcommon/container_registry.hcl")
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"

  # Mock outputs for plan and validation
  mock_outputs = {
    container_registry = "mockacr"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"

  # Mock outputs for plan and validation
  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

# AKS dependency for integration
dependency "aks_core" {
  config_path = "../aks_core"

  # Mock outputs for plan and validation
  mock_outputs = {
    kubelet_identity = {
      client_id = "00000000-0000-0000-0000-000000000000"
      object_id = "00000000-0000-0000-0000-000000000000"
      user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
    }
  }
}

# Specify the Terraform module to use - this will be merged with the common configuration
terraform {
  source = "${get_repo_root()}/infra/modules/azure/container_registry"
}

# Inputs for the Container Registry module - these will be merged with common inputs
inputs = {
  create = true

  # Environment variables
  environment = include.base.locals.env
  workload = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  # Resource details
  name                = dependency.naming.outputs.container_registry
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location

  # Registry configuration - specific to this environment
  sku                           = "Standard"
  public_network_access_enabled = true

  # AKS integration with specific AKS instance
  aks_principal_id = dependency.aks_core.outputs.kubelet_identity.object_id

  # Tags specific to this environment - will be merged with common tags
  tags = merge(include.base.locals.tags, {
    purpose      = "container-registry"
    application  = "kubernetes-workloads"
    integration  = "aks"
  })
}
