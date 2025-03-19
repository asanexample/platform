variables {
  prefix             = "vip"
  customer           = null
  stage              = "dev"
  region_abbv        = "eus"
  
  resource_group_name = "rg-test-aks-core-001"
  location           = "eastus"
  dns_prefix         = "test-aks-core"
  
  # Identity configuration
  identity_type      = "SystemAssigned"
  
  # Default node pool
  default_nodepool_name = "system"
  default_nodepool_vm_size = "Standard_D2s_v4"
  default_nodepool_count = 1
  
  # Tags
  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

run "validate_aks_cluster_creation" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.name == "vip-dev-aks-eus"
    error_message = "AKS cluster name does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.resource_group_name == var.resource_group_name
    error_message = "AKS cluster resource group does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.location == var.location
    error_message = "AKS cluster location does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.dns_prefix == var.dns_prefix
    error_message = "AKS cluster DNS prefix does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].name == var.default_nodepool_name
    error_message = "Default node pool name does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].node_count == var.default_nodepool_count
    error_message = "Default node pool count does not match expected value"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.identity[0].type == "SystemAssigned"
    error_message = "Identity type does not match expected value"
  }
  
  assert {
    condition     = length(azurerm_kubernetes_cluster.aks_cluster.tags) > 0
    error_message = "Tags were not applied correctly"
  }
}

run "validate_custom_name" {
  command = plan
  
  variables {
    name = "custom-aks-cluster"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.name == "custom-aks-cluster"
    error_message = "Custom cluster name was not applied correctly"
  }
}

run "validate_workload_identity_disabled" {
  command = plan
  
  variables {
    workload_identity_enabled = false
    oidc_issuer_enabled = false
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.workload_identity_enabled == false
    error_message = "Workload identity should be disabled"
  }
  
  assert {
    condition     = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_enabled == false
    error_message = "OIDC issuer should be disabled"
  }
} 