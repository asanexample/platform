# Terragrunt configuration for Azure aks_core in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "east"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the aks_core module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/aks_core"
}
# Set dependencies for this module
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
  }
}

dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
  }
}

dependency "networking" {
  config_path = "../networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    subnet_ids = { 
      "az1-kubernetes" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-kubernetes"
    }
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  cluster_name        = dependency.naming.outputs.aks_cluster
  kubernetes_version  = "1.27"
  identity_type       = "UserAssigned"
  user_assigned_identity_id = dependency.aks_identity.outputs.id
  subnet_id           = dependency.networking.outputs.subnet_ids["az1-kubernetes"]
  prefix              = local.prefix
  environment         = local.env
  region_abbv         = local.region_abbv
  customer            = local.customer
  default_nodepool_node_labels = {
    "nodepool-type" = "system"
    "environment"   = local.env
    "region"        = local.region
  }
  network_plugin     = "azure"
  network_policy     = "azure"
  service_cidr       = "10.0.0.0/16"
  dns_service_ip     = "10.0.0.10"
  tags               = local.tags
}

