variables {
  prefix      = "vip"
  customer    = null
  stage       = "dev"
  region_abbv = "eus"
  
  # AKS cluster ID - mock value for testing
  aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test-aks-001/providers/Microsoft.ContainerService/managedClusters/aks-test-001"
  
  # App node pool
  app_node_pool_enabled = true
  app_node_pool_name = "apps"
  app_node_pool_vm_size = "Standard_D4s_v4"
  app_node_pool_node_count = 2
  app_node_pool_os_disk_size_gb = 128
  app_node_pool_max_pods = 30
  
  # Auto-scaling
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count = 1
  app_node_pool_max_count = 5
  
  # Tags
  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

run "validate_app_node_pool_creation" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.app_node_pool[0].name == "vipdevnp"
    error_message = "App node pool name does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.app_node_pool[0].kubernetes_cluster_id == var.aks_cluster_id
    error_message = "AKS cluster ID does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.app_node_pool[0].vm_size == var.app_node_pool_vm_size
    error_message = "VM size does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.app_node_pool[0].enable_auto_scaling == var.app_node_pool_enable_auto_scaling
    error_message = "Auto-scaling flag does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.app_node_pool[0].min_count == var.app_node_pool_min_count
    error_message = "Min count does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.app_node_pool[0].max_count == var.app_node_pool_max_count
    error_message = "Max count does not match expected value"
  }
  
  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.app_node_pool[0].tags) > 0
    error_message = "Tags were not applied correctly"
  }
}

run "validate_no_node_pool" {
  command = plan
  
  variables {
    app_node_pool_enabled = false
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.app_node_pool) == 0
    error_message = "App node pool should not be created when disabled"
  }
} 