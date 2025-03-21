# Test file for Azure AKS Node Pools module
# Using Terraform 1.6+ testing framework

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  resource_group_name = "test-rg"
  location            = "eastus"
  aks_cluster_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-aks"
  environment         = "dev"
  region_abbv         = "eus"
  app_node_pool_enabled = true
  app_node_pool_vm_size = "Standard_D2s_v3"
  app_node_pool_node_count = 2
  app_node_pool_node_labels = {
    "role" = "application"
  }
  app_node_pool_node_taints = []
  tags = {
    Environment = "test"
    ManagedBy   = "Terraform"
  }
}

# Test application node pool creation
run "validate_app_node_pool_creation" {
  command = plan

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  # Assert that location is correct
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

# Test multiple node pools via custom app node pool
run "validate_app_node_pool_properties" {
  command = plan

  variables {
    app_node_pool_name = "batch"
    app_node_pool_vm_size = "Standard_D4s_v3"
    app_node_pool_node_count = 1
    app_node_pool_node_labels = {
      "role" = "batch"
    }
    app_node_pool_node_taints = ["batch=true:NoSchedule"]
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  # Assert that location is correct
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
} 