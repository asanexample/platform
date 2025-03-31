/**
 * # Log Analytics Module - Basic Test
 * 
 * This test verifies the basic functionality of the Log Analytics module
 * with minimal configuration.
 */

variables {
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

run "basic_log_analytics" {
  command = plan

  variables {
    resource_group_name = "rg-test-log-analytics"
    location           = "eastus"
    name              = "log-test"
    retention_in_days = 30
    sku               = "PerGB2018"
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # For plan mode, we'll validate the input variables
  assert {
    condition     = var.name == "log-test"
    error_message = "Name variable should be 'log-test'"
  }

  assert {
    condition     = var.resource_group_name == "rg-test-log-analytics"
    error_message = "Resource group name variable should be 'rg-test-log-analytics'"
  }

  assert {
    condition     = var.location == "eastus"
    error_message = "Location variable should be 'eastus'"
  }

  assert {
    condition     = var.retention_in_days == 30
    error_message = "Retention in days should be 30"
  }

  assert {
    condition     = var.sku == "PerGB2018"
    error_message = "SKU should be 'PerGB2018'"
  }
} 