/**
 * # AKS Node Pools Module - Basic Test
 * 
 * This test verifies the basic functionality of the AKS Node Pools module
 * with minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id                 = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id                       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Basic test for AKS Node Pools with minimal configuration
run "basic_aks_node_pools" {
  command = plan

  variables {
    # Basic naming
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"

    # Reference to existing AKS cluster
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-dev-aks-eus"

    # App node pool configuration
    app_node_pool_enabled            = true
    app_node_pool_name               = "apps"
    app_node_pool_vm_size            = "Standard_D4s_v4"
    app_node_pool_node_count         = 2
    app_node_pool_availability_zones = ["1", "2", "3"]
    app_node_pool_max_pods           = 110
    app_node_pool_os_disk_size_gb    = 128
    app_node_pool_os_disk_type       = "Managed"

    # No auto-scaling for basic test
    app_node_pool_enable_auto_scaling = false

    # User mode for app node pool
    app_node_pool_mode = "User"

    # Basic labels and no taints
    app_node_pool_node_labels = {
      "nodepool"    = "apps"
      "app"         = "true"
      "environment" = "dev"
    }
    app_node_pool_node_taints = []

    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  # Validate node pool properties
  assert {
    condition     = output.app_node_pool_name == "apps"
    error_message = "App node pool name doesn't match expected value"
  }

  assert {
    condition     = output.app_node_pool_node_count == 2
    error_message = "App node pool node count doesn't match expected value"
  }

  assert {
    condition     = output.app_node_pool_vm_size == "Standard_D4s_v4"
    error_message = "App node pool VM size doesn't match expected value"
  }

  assert {
    condition     = output.app_node_pool_os_disk_size_gb == 128
    error_message = "App node pool OS disk size doesn't match expected value"
  }

  assert {
    condition     = output.app_node_pool_auto_scaling_enabled == false
    error_message = "App node pool auto-scaling should be disabled"
  }

  assert {
    condition     = output.app_node_pool_mode == "User"
    error_message = "App node pool mode doesn't match expected value"
  }

  assert {
    condition     = output.app_node_pool_node_labels["environment"] == "dev"
    error_message = "App node pool labels don't match expected values"
  }
} 