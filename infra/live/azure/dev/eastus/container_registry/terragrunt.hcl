# Terragrunt configuration for Azure Container Registry in eastus region

# Local variables for this configuration
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Merge all variables for convenience
  all_vars = merge(
    local.env_vars.locals,
    local.region_vars.locals,
    local.network_vars.locals,
    local.common_vars.locals
  )
  
  # Extract commonly used variables
  env         = local.env_vars.locals.environment
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  tags        = merge(
    local.common_vars.locals.tags, 
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
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
    container_registry = "mock-acr"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"

  # Mock outputs for plan and validation
  mock_outputs = {
    name     = "mock-rg"
    location = local.region
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
  source = "${get_parent_terragrunt_dir()}/../../modules/azure/container_registry"
}

# Inputs for the Container Registry module - these will be merged with common inputs
inputs = {
  # Environment variables
  environment = local.env
  prefix = local.prefix
  region_abbv = local.region_abbv

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
  tags = merge(local.tags, {
    purpose      = "container-registry"
    application  = "kubernetes-workloads"
    integration  = "aks"
  })
} 