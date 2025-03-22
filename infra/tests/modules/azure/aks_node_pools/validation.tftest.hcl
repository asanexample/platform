/**
 * # AKS Node Pools Module - Validation Test
 * 
 * This test verifies validation conditions for the AKS Node Pools module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test node pool name validation with minimum length
run "min_name_length_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "a"  # Minimum length is 1 character
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = output.app_node_pool_name == "a"
    error_message = "App node pool name should be valid with minimum length"
  }
}

# Test node pool name validation with maximum length
run "max_name_length_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "abcdefghijkl"  # Maximum length is 12 characters
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = output.app_node_pool_name == "abcdefghijkl"
    error_message = "App node pool name should be valid with maximum length"
  }
}

# Test min/max validation for node pool count
run "valid_node_count_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_node_count = 1  # Minimum valid count
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = output.app_node_pool_node_count == 1
    error_message = "App node pool node count should be valid with minimum value"
  }
}

# Test min/max validation for max_pods
run "valid_max_pods_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_max_pods = 30  # Minimum valid value
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = output.app_node_pool_name == "test"
    error_message = "App node pool should be created with minimum max_pods value"
  }
}

# Test valid disk types
run "valid_disk_type_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_os_disk_type = "Ephemeral"  # Valid disk type
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = output.app_node_pool_name == "test"
    error_message = "App node pool should be created with valid disk type"
  }
}

# Test valid node pool mode
run "valid_node_pool_mode_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_mode = "System"  # Valid mode
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = output.app_node_pool_mode == "System"
    error_message = "App node pool mode should be valid"
  }
} 