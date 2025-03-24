/**
 * # Monitor Workspace Module - Advanced Test
 * 
 * This test verifies advanced functionality of the Monitor workspace module
 * including integration with other resources.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test location constraints in plan mode to validate resource locations
run "monitor_workspace_location_test" {
  command = plan

  variables {
    name                = "eastus2-monitor-ws"
    resource_group_name = "test-rg"
    location            = "eastus2"
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Verify all resources use the same location as input
  assert {
    condition     = azurerm_monitor_workspace.prometheus.location == "eastus2"
    error_message = "Monitor workspace location should match the input location"
  }
  
  assert {
    condition     = azurerm_monitor_data_collection_endpoint.prometheus.location == "eastus2"
    error_message = "Data Collection Endpoint location should match the input location"
  }
  
  assert {
    condition     = azurerm_monitor_data_collection_rule.prometheus.location == "eastus2"
    error_message = "Data Collection Rule location should match the input location"
  }
}

# Test western region
run "monitor_workspace_west_region" {
  command = plan

  variables {
    name                = "westus2-monitor-ws"
    resource_group_name = "test-rg"
    location            = "westus2"
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Validate workspace uses correct region
  assert {
    condition     = azurerm_monitor_workspace.prometheus.location == "westus2"
    error_message = "Monitor workspace location should match westus2"
  }
  
  # Validate resources are named correctly
  assert {
    condition     = azurerm_monitor_workspace.prometheus.name == "westus2-monitor-ws"
    error_message = "Monitor workspace name should match input"
  }
}

# Test with custom resource group name
run "monitor_workspace_custom_rg" {
  command = plan

  variables {
    name                = "custom-rg-monitor-ws"
    resource_group_name = "custom-monitoring-rg"
    location            = "eastus"
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Validate resources are created in the custom resource group
  assert {
    condition     = azurerm_monitor_workspace.prometheus.resource_group_name == "custom-monitoring-rg"
    error_message = "Monitor workspace should use the custom resource group"
  }
  
  assert {
    condition     = azurerm_monitor_data_collection_endpoint.prometheus.resource_group_name == "custom-monitoring-rg"
    error_message = "Data Collection Endpoint should use the custom resource group"
  }
  
  assert {
    condition     = azurerm_monitor_data_collection_rule.prometheus.resource_group_name == "custom-monitoring-rg"
    error_message = "Data Collection Rule should use the custom resource group"
  }
}

# Test DCR configuration details
run "monitor_workspace_dcr_config" {
  command = plan

  variables {
    name                = "dcr-config-test-ws"
    resource_group_name = "test-rg"
    location            = "eastus"
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Validate DCR configuration
  assert {
    condition     = azurerm_monitor_data_collection_rule.prometheus.kind == "Linux"
    error_message = "Data Collection Rule kind should be Linux"
  }
  
  # Validate DCE configuration
  assert {
    condition     = azurerm_monitor_data_collection_endpoint.prometheus.kind == "Linux"
    error_message = "Data Collection Endpoint kind should be Linux"
  }
  
  # Validate the DCR has destinations configured
  assert {
    condition     = length(azurerm_monitor_data_collection_rule.prometheus.destinations) > 0
    error_message = "Data Collection Rule should have destinations configured"
  }
  
  # Validate the DCR has a monitor_account destination
  assert {
    condition     = length(azurerm_monitor_data_collection_rule.prometheus.destinations[0].monitor_account) > 0
    error_message = "Data Collection Rule should have a monitor account destination"
  }
  
  # Validate data sources configuration
  assert {
    condition     = length(azurerm_monitor_data_collection_rule.prometheus.data_sources) > 0
    error_message = "Data Collection Rule should have data sources configured"
  }
} 