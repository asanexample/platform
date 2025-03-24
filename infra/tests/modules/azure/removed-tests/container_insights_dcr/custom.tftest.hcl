/**
 * # Container Insights DCR Module - Custom Configuration Test
 * 
 * This test verifies the functionality of the Container Insights DCR module with custom configurations.
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

# Test with custom configuration options
run "custom_container_insights_dcr" {
  command = plan

  variables {
    resource_group_name       = "custom-rg"
    location                  = "westus2"
    cluster_name              = "custom-aks"
    cluster_id                = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/custom-rg/providers/Microsoft.ContainerService/managedClusters/custom-aks"
    log_analytics_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/custom-rg/providers/Microsoft.OperationalInsights/workspaces/custom-workspace"
    
    # Custom data streams
    data_streams = [
      "Microsoft-ContainerLogV2",
      "Microsoft-KubeEvents"
    ]
    
    # Custom tags
    tags = {
      environment = "test"
      component   = "monitoring"
      owner       = "platform-team"
    }
  }

  module {
    source = "../../../../modules/azure/container_insights_dcr"
  }

  # Verify DCR name format
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.name == "MSCI-westus2-custom-aks"
    error_message = "DCR name should follow the pattern 'MSCI-{location}-{cluster_name}'"
  }
  
  # Verify resource group name
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.resource_group_name == "custom-rg"
    error_message = "Resource group should be set correctly"
  }
  
  # Verify location
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.location == "westus2"
    error_message = "Location should be set correctly"
  }
  
  # Verify custom data streams
  assert {
    condition     = length(azurerm_monitor_data_collection_rule.container_insights.data_flow[0].streams) == 2
    error_message = "Data streams should have 2 entries"
  }
  
  # Verify custom tags
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.tags["environment"] == "test"
    error_message = "Environment tag should be set correctly"
  }
  
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.tags["component"] == "monitoring"
    error_message = "Component tag should be set correctly"
  }
  
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.tags["owner"] == "platform-team"
    error_message = "Owner tag should be set correctly"
  }
  
  # Verify DCR association has correct name
  assert {
    condition     = azurerm_monitor_data_collection_rule_association.container_insights.name == "custom-aks-container-insights"
    error_message = "DCR association name should follow the pattern '{cluster_name}-container-insights'"
  }
} 