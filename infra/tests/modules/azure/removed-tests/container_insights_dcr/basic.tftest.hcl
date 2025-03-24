/**
 * # Container Insights DCR Module - Basic Test
 * 
 * This test verifies the basic functionality of the Container Insights DCR module
 * with minimal configuration.
 */

# Provider configuration with mock credentials for testing
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
  use_msi = false
}

# Variables for Azure credentials passed via environment variables
variables {
  subscription_id = ""
  tenant_id = ""
}

# Basic test for Container Insights DCR creation with minimal configuration
run "basic_container_insights_dcr" {
  command = plan

  variables {
    resource_group_name        = "test-rg"
    location                   = "eastus"
    cluster_name               = "test-aks"
    cluster_id                 = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-aks"
    log_analytics_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-workspace"
    
    # Default data streams
    data_streams = [
      "Microsoft-ContainerLogV2",
      "Microsoft-ContainerInsights-Group-Default"
    ]
    
    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/container_insights_dcr"
  }

  # Verify DCR name format
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.name == "MSCI-eastus-test-aks"
    error_message = "DCR name should follow the pattern 'MSCI-{location}-{cluster_name}'"
  }
  
  # Verify resource group name
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.resource_group_name == "test-rg"
    error_message = "Resource group should be set correctly"
  }
  
  # Verify location
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.location == "eastus"
    error_message = "Location should be set correctly"
  }
  
  # Verify data flow streams
  assert {
    condition     = length(azurerm_monitor_data_collection_rule.container_insights.data_flow[0].streams) > 0
    error_message = "Data flow streams should not be empty"
  }
  
  # Verify DCR association has correct name
  assert {
    condition     = azurerm_monitor_data_collection_rule_association.container_insights.name == "test-aks-container-insights"
    error_message = "DCR association name should follow the pattern '{cluster_name}-container-insights'"
  }
  
  # Verify DCR association has correct target ID
  assert {
    condition     = azurerm_monitor_data_collection_rule_association.container_insights.target_resource_id == "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.ContainerService/managedClusters/test-aks"
    error_message = "DCR association target resource ID should match the cluster ID"
  }
} 