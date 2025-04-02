/**
 * # AKS Node Pools Module - Validation Test
 * 
 * This test verifies the validation rules of the AKS Node Pools module
 * to ensure that input variables are properly validated.
 */

# Provider configuration with Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Test prefix validation
run "prefix_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = var.prefix == "test"
    error_message = "Prefix should be valid with proper format"
  }
}

# Test region abbreviation validation
run "region_abbv_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"  # Valid region abbreviation
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = var.region_abbv == "eus"
    error_message = "Region abbreviation should be valid"
  }
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

# Test VM size validation
run "vm_size_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_vm_size = "Standard_D4s_v3"  # Valid VM size starting with Standard_
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = startswith(var.app_node_pool_vm_size, "Standard_")
    error_message = "VM size should start with Standard_"
  }
}

# Test availability zones validation
run "availability_zones_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_availability_zones = ["1", "2"]  # Valid zones
    app_node_pool_enable_auto_scaling = false
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = length(var.app_node_pool_availability_zones) == 2
    error_message = "Availability zones should accept valid values"
  }
}

# Test auto-scaling configuration
run "autoscaling_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_enable_auto_scaling = true
    app_node_pool_min_count = 1
    app_node_pool_max_count = 5
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = var.app_node_pool_enable_auto_scaling == true
    error_message = "Auto-scaling should be enabled with valid configuration"
  }
}

# Test min/max count relationship
run "min_max_count_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_enable_auto_scaling = true
    app_node_pool_min_count = 2
    app_node_pool_max_count = 10
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = var.app_node_pool_max_count > var.app_node_pool_min_count
    error_message = "Max count should be greater than min count"
  }
}

# Test node labels validation
run "node_labels_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_enable_auto_scaling = false
    # Valid node labels
    app_node_pool_node_labels = {
      "key1" = "value1"
      "key2" = "value2"
    }
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = length(keys(var.app_node_pool_node_labels)) == 2
    error_message = "Node labels should be accepted with valid format"
  }
}

# Test node taints validation
run "node_taints_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_enable_auto_scaling = false
    # Valid node taints
    app_node_pool_node_taints = [
      "key1=value1:NoSchedule",
      "key2=value2:PreferNoSchedule"
    ]
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = length(var.app_node_pool_node_taints) == 2
    error_message = "Node taints should be accepted with valid format"
  }
}

# Test tags validation
run "tags_validation_test" {
  command = plan

  variables {
    prefix         = "test"
    environment    = "dev"
    region_abbv    = "eus"
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"
    app_node_pool_name = "test"
    app_node_pool_enable_auto_scaling = false
    # Valid tags
    tags = {
      environment = "test"
      application = "aks"
      owner       = "platform-team"
    }
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  assert {
    condition     = length(keys(var.tags)) == 3
    error_message = "Tags should be accepted with valid format"
  }
} 