# Terragrunt configuration for the AKS cluster composite module

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependencies
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = "mock-rg"
    aks_cluster = "mock-aks"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Configure the module source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/aks_cluster_composite"
}

# Default inputs for the AKS cluster composite module (overridden by environments)
inputs = {
  # Use create_resources flag to allow enabling/disabling AKS cluster creation
  create_resources = true
  
  # Naming inputs
  prefix      = "vip"
  customer    = null
  stage       = "dev"
  region_abbv = "eus"
  
  # Resource location and group
  resource_group_name = dependency.naming.outputs.resource_group
  location            = "eastus"
  
  # Leave name as null to use naming module for generating cluster name
  name = null
  
  # Default AKS cluster settings
  kubernetes_version = "1.28.3"
  sku_tier           = "Standard"
  
  # Default networking settings
  network_plugin      = "azure"
  network_plugin_mode = null
  network_policy      = "calico"
  network_data_plane  = null
  pod_cidr            = null
  service_cidr        = "10.0.0.0/16"
  dns_service_ip      = "10.0.0.10"
  docker_bridge_cidr  = null
  
  # Default to empty subnet (will be set in environment-specific config)
  subnet_id = null
  
  # AZ settings
  availability_zones = ["1", "2", "3"]
  
  # Identity and monitoring
  workload_identity_enabled  = true
  oidc_issuer_enabled        = true
  local_account_disabled     = false
  log_analytics_workspace_id = null
  
  # Default to public cluster
  private_cluster_enabled             = false
  private_dns_zone_id                 = null
  private_cluster_public_fqdn_enabled = true
  authorized_ip_ranges                = null
  
  # Tags
  tags = {
    ManagedBy   = "Terragrunt"
    Component   = "AKS"
  }
} 