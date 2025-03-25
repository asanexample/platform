/**
 * # Managed Grafana Module - Basic Test
 * 
 * This test verifies the basic functionality of the managed grafana module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test with minimal configuration
run "basic_grafana" {
  command = plan

  variables {
    name                = "test-grafana-basic"
    resource_group_name = "test-rg"
    location            = "eastus"
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify Grafana resource is created with default values
  assert {
    condition     = azurerm_dashboard_grafana.grafana.name == "test-grafana-basic"
    error_message = "Grafana resource should be created with the correct name"
  }
  
  assert {
    condition     = azurerm_dashboard_grafana.grafana.resource_group_name == "test-rg"
    error_message = "Grafana resource should be in the correct resource group"
  }
  
  assert {
    condition     = azurerm_dashboard_grafana.grafana.location == "eastus"
    error_message = "Grafana resource should be in the correct location"
  }
  
  assert {
    condition     = azurerm_dashboard_grafana.grafana.api_key_enabled == true
    error_message = "Grafana API key should be enabled by default"
  }
  
  assert {
    condition     = azurerm_dashboard_grafana.grafana.public_network_access_enabled == true
    error_message = "Grafana public network access should be enabled by default"
  }
  
  assert {
    condition     = azurerm_dashboard_grafana.grafana.zone_redundancy_enabled == true
    error_message = "Grafana zone redundancy should be enabled by default"
  }
  
  assert {
    condition     = azurerm_dashboard_grafana.grafana.grafana_major_version == "10"
    error_message = "Grafana version should be 10 by default"
  }
} 