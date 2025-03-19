# Terragrunt configuration for Azure AKS Core in westus region

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

# Use the AKS core module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/aks_core"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
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
    subnet_ids = {
      "az1-node-subnet" = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-node-subnet"
    }
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
    principal_id = "mock-principal-id"
    client_id = "mock-client-id"
  }
}

dependency "aks_networking" {
  config_path = "../aks_networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    private_dns_zone_id = null
    network_security_group_id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/networkSecurityGroups/mock-nsg"
  }
}

# Specify inputs specific to this module
inputs = {
  # Naming
  prefix      = local.prefix
  customer    = local.customer
  stage       = local.env
  region_abbv = local.region_abbv
  name        = dependency.naming.outputs.aks_cluster
  
  # Resource details
  resource_group_name = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location
  dns_prefix = "${local.prefix}-${local.env}-wus"
  
  # Cluster configuration
  kubernetes_version = "1.26.6"
  sku_tier = "Standard" # Required when cost_analysis_enabled is true
  local_account_disabled = true
  workload_identity_enabled = true
  oidc_issuer_enabled = true
  
  # Identity configuration - use the user-assigned identity
  identity_type = "UserAssigned"
  user_assigned_identity_id = dependency.aks_identity.outputs.id
  
  # Network profile configuration
  network_plugin = "azure"
  network_policy = "azure"
  pod_cidr = "10.244.0.0/16"
  service_cidr = "10.0.0.0/16"
  dns_service_ip = "10.0.0.10"
  docker_bridge_cidr = "172.17.0.1/16"
  subnet_id = dependency.networking.outputs.subnet_ids["az1-node-subnet"]
  
  # Private cluster configuration
  private_cluster_enabled = true
  private_dns_zone_id = dependency.aks_networking.outputs.private_dns_zone_id
  
  # Default node pool
  default_nodepool_name = "system"
  default_nodepool_vm_size = "Standard_D2s_v4"
  default_nodepool_count = 2
  default_nodepool_enable_auto_scaling = true
  default_nodepool_min_count = 2
  default_nodepool_max_count = 3
  default_nodepool_max_pods = 30
  default_nodepool_os_disk_size_gb = 128
  default_nodepool_node_labels = {
    "role" = "system"
  }
  
  # Tags
  tags = local.tags
} 