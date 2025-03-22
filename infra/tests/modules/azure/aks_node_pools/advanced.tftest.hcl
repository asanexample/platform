/**
 * # AKS Node Pools Module - Advanced Test
 * 
 * This test verifies advanced functionality of the AKS Node Pools module
 * including auto-scaling, taints, and custom configurations.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Advanced test for AKS Node Pools with auto-scaling and taints
run "advanced_aks_node_pools" {
  command = plan

  variables {
    # Basic naming
    prefix      = "test"
    environment = "prod"
    region_abbv = "eus"
    customer    = "enterprise"
    
    # Reference to existing AKS cluster
    aks_cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-prod-aks-eus"
    
    # App node pool configuration with advanced settings
    app_node_pool_enabled           = true
    app_node_pool_name              = "webapp"
    app_node_pool_vm_size           = "Standard_D8s_v4"
    app_node_pool_node_count        = 3
    app_node_pool_availability_zones = ["1", "2", "3"]
    app_node_pool_max_pods          = 150
    app_node_pool_os_disk_size_gb   = 256
    app_node_pool_os_disk_type      = "Ephemeral"
    
    # Enable auto-scaling with custom min/max values
    app_node_pool_enable_auto_scaling = true
    app_node_pool_min_count         = 2
    app_node_pool_max_count         = 8
    
    # System mode for critical applications
    app_node_pool_mode = "System"
    
    # Advanced labels and taints
    app_node_pool_node_labels = {
      "nodepool"      = "webapp"
      "app"           = "true"
      "environment"   = "production"
      "criticality"   = "high"
      "security-tier" = "restricted"
      "workload-type" = "web"
    }
    app_node_pool_node_taints = [
      "workload-type=webapp:NoSchedule",
      "security-tier=restricted:NoExecute"
    ]
    
    # Temporary name for rotation - fixed to comply with AKS naming requirements
    temporary_name_for_rotation = "webtemp"
    
    # Comprehensive tagging
    tags = {
      environment     = "production"
      criticality     = "high"
      data-class      = "confidential"
      service-owner   = "platform-team"
      cost-center     = "12345"
      application     = "core-infrastructure"
    }
  }

  module {
    source = "../../../../modules/azure/aks_node_pools"
  }

  # Validate node pool properties
  assert {
    condition     = output.app_node_pool_name == "webapp"
    error_message = "App node pool name doesn't match expected value"
  }
  
  assert {
    condition     = output.app_node_pool_vm_size == "Standard_D8s_v4"
    error_message = "App node pool VM size doesn't match expected value"
  }
  
  assert {
    condition     = output.app_node_pool_os_disk_size_gb == 256
    error_message = "App node pool OS disk size doesn't match expected value"
  }
  
  assert {
    condition     = output.app_node_pool_auto_scaling_enabled == true
    error_message = "App node pool auto-scaling should be enabled"
  }
  
  assert {
    condition     = output.app_node_pool_min_count == 2
    error_message = "App node pool minimum count doesn't match expected value"
  }
  
  assert {
    condition     = output.app_node_pool_max_count == 8
    error_message = "App node pool maximum count doesn't match expected value"
  }
  
  assert {
    condition     = output.app_node_pool_mode == "System"
    error_message = "App node pool mode doesn't match expected value"
  }
  
  assert {
    condition     = output.app_node_pool_node_labels["criticality"] == "high"
    error_message = "App node pool labels don't match expected values"
  }
} 