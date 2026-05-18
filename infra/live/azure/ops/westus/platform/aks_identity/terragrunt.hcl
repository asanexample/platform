# Terragrunt configuration for Azure AKS Identity in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root configuration (root.hcl)
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include the common configuration for AKS Identity
include "aks_identity_common" {
  path = find_in_parent_folders("azure/_envcommon/aks_identity.hcl")
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"

  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster  = "mock-aks"
    aks_identity = "mock-identity"
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

dependency "networking" {
  config_path = "../networking"

  # Mock outputs for plan and validation
  mock_outputs = {
    vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  create = true

  # Identity naming
  aks_identity_name = dependency.naming.outputs.aks_identity
  cluster_name      = dependency.naming.outputs.aks_cluster

  # Environment variables
  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  # Resource details
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location

  # Environment-specific configuration
  create_workload_identities = false
  workload_identity_enabled  = false
  oidc_issuer_enabled        = false

  # Role assignments with specific scopes for this environment
  role_assignments = {
    "Network Contributor" = {
      scope                            = dependency.networking.outputs.vnet_id
      skip_service_principal_aad_check = true
    }
  }
}
