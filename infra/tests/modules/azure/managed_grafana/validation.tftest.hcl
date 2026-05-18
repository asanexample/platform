/**
 * # Managed Grafana Module - Validation Test
 * 
 * This test verifies validation conditions for the managed grafana module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test basic configuration with default values
run "basic_configuration_test" {
  command = plan

  variables {
    name                    = "test-grafana"
    resource_group_name     = "test-rg"
    location                = "eastus"
    prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify Grafana resource is created
  assert {
    condition     = azurerm_dashboard_grafana.grafana.name == "test-grafana"
    error_message = "Grafana resource should be created with the correct name"
  }

  # Verify Grafana has the correct properties
  assert {
    condition     = azurerm_dashboard_grafana.grafana.resource_group_name == "test-rg"
    error_message = "Grafana resource should be in the correct resource group"
  }

  # Verify Prometheus integration is configured
  assert {
    condition     = azurerm_dashboard_grafana.grafana.azure_monitor_workspace_integrations[0].resource_id == var.prometheus_workspace_id
    error_message = "Grafana should be integrated with the Prometheus workspace"
  }
}

# Test with API key disabled
run "api_key_disabled_test" {
  command = plan

  variables {
    name                    = "test-grafana"
    resource_group_name     = "test-rg"
    location                = "eastus"
    prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    api_key_enabled         = false
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify API key is disabled
  assert {
    condition     = azurerm_dashboard_grafana.grafana.api_key_enabled == false
    error_message = "Grafana should have API key disabled"
  }
}

# Test with public network access disabled
run "public_network_disabled_test" {
  command = plan

  variables {
    name                          = "test-grafana"
    resource_group_name           = "test-rg"
    location                      = "eastus"
    prometheus_workspace_id       = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    public_network_access_enabled = false
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify public network access is disabled
  assert {
    condition     = azurerm_dashboard_grafana.grafana.public_network_access_enabled == false
    error_message = "Grafana should have public network access disabled"
  }
}

# Test with zone redundancy disabled
run "zone_redundancy_disabled_test" {
  command = plan

  variables {
    name                    = "test-grafana"
    resource_group_name     = "test-rg"
    location                = "eastus"
    prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    zone_redundancy_enabled = false
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify zone redundancy is disabled
  assert {
    condition     = azurerm_dashboard_grafana.grafana.zone_redundancy_enabled == false
    error_message = "Grafana should have zone redundancy disabled"
  }
}

# Test with specific Grafana version
run "grafana_version_test" {
  command = plan

  variables {
    name                    = "test-grafana"
    resource_group_name     = "test-rg"
    location                = "eastus"
    prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    grafana_major_version   = "11" # Updated to use a newer supported version
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify Grafana version is set correctly
  assert {
    condition     = azurerm_dashboard_grafana.grafana.grafana_major_version == "11"
    error_message = "Grafana version should be set to 11"
  }
} 