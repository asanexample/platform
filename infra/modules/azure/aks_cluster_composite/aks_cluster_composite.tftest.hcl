# Test file for AKS Cluster Composite module
# Using Terraform 1.6+ testing framework

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
  use_cli = true
}

# Define basic test variables
variables {
  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "vip"
  customer            = "test"
  stage               = "dev"
  region_abbv         = "eus"
  name                = "test-aks"

  # Network configuration
  subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-network-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-monitoring-rg/providers/Microsoft.OperationalInsights/workspaces/test-workspace"
  network_data_plane         = "azure"

  # Basic configuration
  kubernetes_version = "1.28.0"

  # Tag all resources
  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
    Project     = "AKS Testing"
    test_mode   = "true"
  }
}

# Basic validation run with minimal configuration
run "basic_validation" {
  command = plan

  # Verify basic configurations
  assert {
    condition     = module.aks_core[0].name == "test-aks"
    error_message = "AKS cluster name does not match expected value"
  }

  # Verify default nodepool configuration
  assert {
    condition     = module.aks_core[0].default_node_pool_name == "system"
    error_message = "Default nodepool name does not match expected value"
  }
}

# Comprehensive run with more specific configuration
run "advanced_configuration" {
  command = plan

  variables {
    # Override basic configuration
    kubernetes_version = "1.29.0"

    # Network configuration
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    private_cluster_enabled = true
  }

  # Verify the kubernetes version
  assert {
    condition     = module.aks_core[0].kubernetes_version == "1.29.0"
    error_message = "Kubernetes version did not match expected value"
  }

  # Verify network plugin
  assert {
    condition     = module.aks_networking[0].network_plugin == "azure"
    error_message = "Network plugin did not match expected value"
  }
} 