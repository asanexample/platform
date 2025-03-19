# Terragrunt configuration for Azure hosting in eastus region

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Include common config for hosting
include "common" {
  path   = "${dirname(find_in_parent_folders())}/live/azure/_envcommon/hosting.hcl"
  expose = true
}

# Include storage configuration
include "storage" {
  path   = "${dirname(find_in_parent_folders())}/live/azure/_envcommon/storage.hcl"
  expose = true
}

# Include region-specific network configuration
locals {
  # Read network configuration from network.hcl in the region directory
  network_config = read_terragrunt_config(find_in_parent_folders("network.hcl"))
}

# Inputs that are the same for all regions
inputs = {
  # Forward network configuration from network.hcl
  address_space = local.network_config.locals.address_space
  subnets       = local.network_config.locals.subnets
  
  # Enable AKS cluster
  create_aks_cluster = true
  
  # AKS cluster configuration
  aks_kubernetes_version = "1.29.0"
  aks_dns_prefix         = "aks-eastus-dev"
  
  # Use network topology for AKS
  aks_use_network_topology     = true
  aks_network_topology_region  = "eastus"
  
  # Configure AKS to use the kubernetes subnets across all AZs
  aks_az_subnet_names = {
    "1" = "az1-kubernetes"
    "2" = "az2-kubernetes" 
    "3" = "az3-kubernetes"
  }
  
  # Use Azure CNI with overlay for optimal pod density
  aks_network_plugin      = "azure"
  aks_network_plugin_mode = "overlay"
  aks_network_policy      = "azure"
  
  # Configure node pools
  aks_default_nodepool_name     = "system"
  aks_default_nodepool_vm_size  = "Standard_D2s_v4"
  aks_default_nodepool_count    = 1
  
  aks_app_node_pool_enabled     = true
  aks_app_node_pool_name        = "app"
  aks_app_node_pool_vm_size     = "Standard_D4s_v4"
  aks_app_node_pool_node_count  = 2
} 