/**
 * # Log Analytics Module - Validation Test
 * 
 * This test verifies validation conditions for the Log Analytics module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test minimum valid retention period
run "min_retention_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = "test-min-retention"
    retention_in_days   = 30  # Minimum allowed
    tags = {}
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  assert {
    condition     = output.name == "test-min-retention"
    error_message = "Log Analytics workspace name doesn't match expected value"
  }
}

# Test maximum valid retention period
run "max_retention_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = "test-max-retention"
    retention_in_days   = 730  # Maximum allowed
    tags = {}
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  assert {
    condition     = output.name == "test-max-retention"
    error_message = "Log Analytics workspace name doesn't match expected value"
  }
}

# Test maximum name length
run "max_name_length_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = "test-workspace-with-maximum-allowed-length-for-log-analytics123" # 63 chars
    tags = {}
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  assert {
    condition     = length(output.name) <= 63
    error_message = "Name should be at most 63 characters (maximum length)"
  }
}

# Test valid SKU
run "valid_sku_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = "test-sku-variants"
    sku                 = "CapacityReservation"
    reservation_capacity_in_gb_per_day = 100  # Only required for CapacityReservation SKU
    tags = {}
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  assert {
    condition     = output.name == "test-sku-variants"
    error_message = "Log Analytics workspace name doesn't match expected value"
  }
} 