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
    vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    vnet_name = "mock-vnet"
    subnet_ids = {
      "az1-kubernetes" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-kubernetes"
    }
    aks_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/privateDnsZones/privatelink.westus.azmk8s.io"
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
}

# This dependency is no longer needed but kept commented for reference
# dependency "aks_networking" {
#   config_path = "../aks_networking"
#   
#   # Mock outputs for plan and validation
#   mock_outputs = {
#     private_dns_zone_id = null
#     network_security_group_id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/networkSecurityGroups/mock-nsg"
#   }
# }

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
  kubernetes_version = "1.32"
  sku_tier = "Standard" # Required when cost_analysis_enabled is true
  local_account_disabled = true  # Re-enable since we're integrating with AAD
  workload_identity_enabled = true
  oidc_issuer_enabled = true
  
  # Azure AD integration - managed approach
  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]  # Replace with actual AAD admin group IDs
    azure_rbac_enabled = true
  }
  
  # Identity configuration - use the user-assigned identity
  identity_type = "UserAssigned"
  user_assigned_identity_id = dependency.aks_identity.outputs.aks_identity_id
  
  # Network profile configuration
  # No CNI will be installed by default; Cilium will be installed separately
  network_plugin = "none"
  
  # Set network_policy to null to avoid conflicts with Cilium installation
  network_policy = null
  
  # Service network configuration
  service_cidr = "10.0.0.0/16"
  dns_service_ip = "10.0.0.10"
  docker_bridge_cidr = "172.17.0.1/16"
  
  # Pod CIDR - will be managed by Cilium
  pod_cidr = "10.244.0.0/16"
  
  # Subnet configuration
  subnet_id = dependency.networking.outputs.subnet_ids["az1-kubernetes"]
  
  # Private cluster configuration
  private_cluster_enabled = true
  private_dns_zone_id = dependency.networking.outputs.aks_private_dns_zone_id
  
  # Default node pool
  default_nodepool_name = "system"
  default_nodepool_vm_size = "Standard_D2s_v4"
  default_nodepool_count = 2
  default_nodepool_enable_auto_scaling = true
  default_nodepool_min_count = 2
  default_nodepool_max_count = 3
  
  # Set max_pods to a higher value since Cilium will be used
  # Cilium can support more pods per node as it uses its own IPAM
  default_nodepool_max_pods = 110
  
  default_nodepool_os_disk_size_gb = 128
  default_nodepool_node_labels = {
    "role" = "system"
    "kubernetes.azure.com/scalesetpriority" = "regular"
  }
  
  # Tags
  tags = merge(local.tags, {
    "network.cilium.io/managed-by" = "cilium"
  })
} 