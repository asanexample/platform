# Test file for AKS Cluster Composite module
# Using Terraform 1.6+ testing framework

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

  # Basic configuration
  kubernetes_version = "1.28.0"

  # Tag all resources
  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
    Project     = "AKS Testing"
  }
}

# Basic validation run with minimal configuration
run "basic_validation" {
  command = plan

  # Assertions for the identity module
  assert {
    condition     = module.aks_identity.aks_identity_id != null
    error_message = "AKS identity was not created properly"
  }

  # Assertions for the core module
  assert {
    condition     = module.aks_core.name == "test-aks"
    error_message = "AKS cluster name does not match expected value"
  }

  # Verify default nodepool configuration
  assert {
    condition     = module.aks_core.default_node_pool_name == "system"
    error_message = "Default nodepool name does not match expected value"
  }

  # Verify workload identity is enabled
  assert {
    condition     = module.aks_core.workload_identity_enabled == true
    error_message = "Workload identity should be enabled"
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
    network_policy      = "azure"
    pod_cidr            = "10.240.0.0/16"
    service_cidr        = "10.1.0.0/16"
    dns_service_ip      = "10.1.0.10"

    # Node pool configuration
    default_nodepool_name    = "systemnodes"
    default_nodepool_vm_size = "Standard_D4s_v4"
    default_nodepool_count   = 2

    # App node pool configuration
    app_node_pool_enabled             = true
    app_node_pool_name                = "appnodes"
    app_node_pool_vm_size             = "Standard_D8s_v4"
    app_node_pool_node_count          = 3
    app_node_pool_enable_auto_scaling = true
    app_node_pool_min_count           = 2
    app_node_pool_max_count           = 10

    # Private cluster configuration
    private_cluster_enabled = true
    private_dns_zone_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns-rg/providers/Microsoft.Network/privateDnsZones/privatelink.eastus.azmk8s.io"
  }

  # Assertions for the core AKS module
  assert {
    condition     = module.aks_core.kubernetes_version == "1.29.0"
    error_message = "Kubernetes version does not match expected value"
  }

  # Assertions for the networking configuration
  assert {
    condition     = module.aks_networking.network_plugin == "azure"
    error_message = "Network plugin does not match expected value"
  }

  assert {
    condition     = module.aks_networking.private_cluster_enabled == true
    error_message = "Private cluster should be enabled"
  }

  # Assertions for node pools
  assert {
    condition     = length(module.aks_node_pools) == 1
    error_message = "Application node pool module should be created"
  }
} 