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

# Include the common configuration for AKS Identity
include "aks_identity_common" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/azure/aks_identity.hcl"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
    aks_identity = "mock-identity"
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

dependency "networking" {
  config_path = "../networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  # Identity naming
  aks_identity_name = dependency.naming.outputs.aks_identity
  cluster_name = dependency.naming.outputs.aks_cluster
  
  # Resource details
  resource_group_name = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location
  
  # Environment-specific configuration
  create_workload_identities = false
  workload_identity_enabled = false
  oidc_issuer_enabled = false
  
  # Role assignments with specific scopes for this environment
  role_assignments = {
    "Network Contributor" = {
      scope = dependency.networking.outputs.vnet_id
      skip_service_principal_aad_check = true
    }
  }
} 