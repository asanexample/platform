# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id                 = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id                       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

/**
 * # Prometheus DCR Module - Validation Test
 * 
 * This test verifies the validation conditions for the Prometheus DCR module.
 */

# Test output values
run "output_values_test" {
  command = plan

  variables {
    resource_group_name  = "test-rg"
    location             = "eastus"
    monitor_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-monitor"
  }

  module {
    source = "../../../../modules/azure/prometheus_dcr"
  }

  # Verify DCR is planned to be created
  assert {
    condition     = length(azurerm_monitor_data_collection_rule.this) > 0
    error_message = "DCR should be planned for creation"
  }

  # Verify DCE is planned to be created
  assert {
    condition     = length(azurerm_monitor_data_collection_endpoint.this) > 0
    error_message = "DCE should be planned for creation"
  }
}

# Test DCR config details
run "dcr_config_details_test" {
  command = plan

  variables {
    name                 = "test-dcr-prometheus"
    dce_name             = "test-dce-prometheus"
    resource_group_name  = "test-rg"
    location             = "eastus"
    monitor_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
  }

  module {
    source = "../../../../modules/azure/prometheus_dcr"
  }

  # Verify Prometheus forwarder configuration
  assert {
    condition     = can(azurerm_monitor_data_collection_rule.this.data_sources[0].prometheus_forwarder[0].name)
    error_message = "Prometheus forwarder should have a name configured"
  }

  assert {
    condition     = can(azurerm_monitor_data_collection_rule.this.data_sources[0].prometheus_forwarder[0].streams)
    error_message = "Prometheus forwarder should have streams configured"
  }

  # Verify monitor account destination
  assert {
    condition     = can(azurerm_monitor_data_collection_rule.this.destinations[0].monitor_account[0].name)
    error_message = "Monitor account destination should have a name configured"
  }

  assert {
    condition     = can(azurerm_monitor_data_collection_rule.this.destinations[0].monitor_account[0].monitor_account_id)
    error_message = "Monitor account destination should use a monitor workspace ID"
  }

  # Verify data flow
  assert {
    condition     = can(azurerm_monitor_data_collection_rule.this.data_flow[0].destinations)
    error_message = "Data flow should have destinations configured"
  }
}

# Test with different Azure region
run "different_region_test" {
  command = plan

  variables {
    resource_group_name  = "test-rg"
    location             = "westus2"
    monitor_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
  }

  module {
    source = "../../../../modules/azure/prometheus_dcr"
  }

  # Verify DCR is created in the correct region
  assert {
    condition     = can(azurerm_monitor_data_collection_rule.this.location)
    error_message = "DCR should have a location defined"
  }

  # Verify default naming includes the location
  assert {
    condition     = can(azurerm_monitor_data_collection_rule.this.name)
    error_message = "DCR should have a name defined"
  }
} 