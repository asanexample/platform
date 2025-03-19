# Terragrunt configuration for Azure AKS in westus region

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

# Use the simpler AKS cluster module as the source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/aks_cluster"
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
    vnet_id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    subnet_ids = {
      "az1-node-subnet" = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-node-subnet"
      "az1-pod-subnet" = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-pod-subnet"
    }
  }
}

dependency "storage" {
  config_path = "../storage"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    storage_account_id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Storage/storageAccounts/mocksa"
  }
}

dependency "keyvault" {
  config_path = "../keyvault"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    key_vault_id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.KeyVault/vaults/mock-kv"
  }
}

# Specify inputs specific to this module
inputs = {
  # Resource group and location
  resource_group_name = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location
  
  # Cluster configuration
  name = dependency.naming.outputs.aks_cluster
  kubernetes_version = "1.26.6"
  dns_prefix = "${local.prefix}-${local.env}-wus"
  
  # Identity configuration
  identity_type = "SystemAssigned"
  
  # Network configuration
  vnet_subnet_id = dependency.networking.outputs.subnet_ids["az1-node-subnet"]
  nodepool_subnet_id = dependency.networking.outputs.subnet_ids["az1-node-subnet"]
  
  # Network profile settings - use explicit empty strings
  network_plugin = "azure"
  network_plugin_mode = ""
  network_policy = "azure"
  network_data_plane = ""
  service_cidr = "10.0.0.0/16"
  dns_service_ip = "10.0.0.10"
  docker_bridge_cidr = "172.17.0.1/16"
  outbound_type = "loadBalancer"
  
  # Security settings
  private_cluster_enabled = true
  api_server_authorized_ip_ranges = ["0.0.0.0/0"]  # This should be restricted in production
  
  # Default node pool
  default_node_pool = {
    name = "system"
    vm_size = "Standard_D2s_v3"
    node_count = 1
    enable_auto_scaling = true
    min_count = 1
    max_count = 3
    max_pods = 30
    os_disk_size_gb = 128
    node_labels = {
      "role" = "system"
    }
    vnet_subnet_id = dependency.networking.outputs.subnet_ids["az1-node-subnet"]
  }

  # RBAC settings
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control = {
    managed = true
    admin_group_object_ids = []
    azure_rbac_enabled = true
  }
  
  # Monitoring configuration - use null values
  log_analytics_workspace_id = null
  monitor_workspace_id = null
  
  # Tags
  tags = local.tags
} 