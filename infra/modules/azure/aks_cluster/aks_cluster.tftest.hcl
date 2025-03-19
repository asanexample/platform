variables {
  name_prefix        = "test"
  name_suffix        = "001"
  resource_group_name = "rg-test-aks-001"
  location           = "westeurope"
  dns_prefix         = "test-aks"
  
  # Identity and access
  identity_ids       = []
  
  # Networking
  network_plugin     = "azure"
  network_policy     = "azure"
  
  # Node pools
  default_node_pool = {
    name                = "system"
    node_count          = 1
    vm_size             = "Standard_D2s_v3"
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"
    max_pods            = 30
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 3
  }
  
  # Monitoring
  log_analytics_workspace_id = null
  
  # Tags
  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

run "validate_aks_cluster_creation" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.aks.name == "aks-test-001"
    error_message = "AKS cluster name does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks.resource_group_name == var.resource_group_name
    error_message = "AKS cluster resource group does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks.location == var.location
    error_message = "AKS cluster location does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks.dns_prefix == var.dns_prefix
    error_message = "AKS cluster DNS prefix does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks.default_node_pool[0].name == var.default_node_pool.name
    error_message = "Default node pool name does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks.default_node_pool[0].node_count == var.default_node_pool.node_count
    error_message = "Default node pool count does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks.network_profile[0].network_plugin == var.network_plugin
    error_message = "Network plugin does not match expected value"
  }
  
  assert {
    condition     = length(azurerm_kubernetes_cluster.aks.tags) == length(var.tags)
    error_message = "Tags do not match expected values"
  }
}

run "validate_private_cluster_configuration" {
  command = plan
  
  variables {
    private_cluster_enabled = true
    private_dns_zone_id = "System"
    authorized_ip_ranges = ["10.0.0.0/24", "192.168.1.0/24"]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks.private_cluster_enabled == true
    error_message = "Private cluster setting does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks.private_dns_zone_id == "System"
    error_message = "Private DNS zone ID does not match expected value"
  }
}

run "validate_with_app_node_pool" {
  command = plan
  
  variables {
    app_node_pool_enabled = true
    app_node_pool = {
      name                = "apps"
      node_count          = 2
      vm_size             = "Standard_D4s_v3"
      os_disk_size_gb     = 128
      os_disk_type        = "Managed"
      max_pods            = 50
      enable_auto_scaling = true
      min_count           = 2
      max_count           = 5
    }
  }

  assert {
    condition     = can(azurerm_kubernetes_cluster_node_pool.app_node_pool)
    error_message = "Application node pool should be created"
  }
} 