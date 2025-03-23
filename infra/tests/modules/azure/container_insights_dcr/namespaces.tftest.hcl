/**
 * # Container Insights DCR Module - Namespace Filtering Test
 * 
 * This test verifies the functionality of namespace filtering options in the DCR.
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

# Test with namespace filtering configuration
run "namespace_filtering_container_insights_dcr" {
  command = plan

  variables {
    resource_group_name        = "ns-test-rg"
    location                   = "eastus"
    cluster_name               = "filtered-aks"
    cluster_id                 = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/ns-test-rg/providers/Microsoft.ContainerService/managedClusters/filtered-aks"
    log_analytics_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/ns-test-rg/providers/Microsoft.OperationalInsights/workspaces/ns-test-workspace"
    
    # Namespace filtering configuration
    namespace_filtering_mode   = "Include"
    namespaces                 = ["kube-system", "monitoring", "ingress-nginx"]
    
    # Additional settings
    interval                   = "PT5M"
    enable_container_log_v2    = true
  }

  module {
    source = "../../../../modules/azure/container_insights_dcr"
  }

  # Verify DCR name format
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.name == "MSCI-eastus-filtered-aks"
    error_message = "DCR name should follow the pattern 'MSCI-{location}-{cluster_name}'"
  }

  # Verify the resource type is correctly set
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.kind == "Linux"
    error_message = "DCR kind should be set to Linux"
  }

  # Verify the data collection rule has an extension
  assert {
    condition     = azurerm_monitor_data_collection_rule.container_insights.data_sources[0].extension[0].extension_name == "ContainerInsights"
    error_message = "Extension name should be ContainerInsights"
  }

  # Verify the DCR association target ID is set correctly
  assert {
    condition     = azurerm_monitor_data_collection_rule_association.container_insights.target_resource_id == "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/ns-test-rg/providers/Microsoft.ContainerService/managedClusters/filtered-aks"
    error_message = "DCR association target resource ID should match the cluster ID"
  }

  # Verify the DCR association name format
  assert {
    condition     = azurerm_monitor_data_collection_rule_association.container_insights.name == "filtered-aks-container-insights"
    error_message = "DCR association name should follow the pattern '{cluster_name}-container-insights'"
  }
} 