/**
 * # Log Analytics Module - Basic Test
 * 
 * This test verifies the basic functionality of the Log Analytics module
 * with minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Basic test for Log Analytics workspace creation with minimal configuration
run "basic_log_analytics_workspace" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Use auto-generated name
    name        = null
    prefix      = "tst"
    environment = "dev"
    region_abbv = "eus"
    
    # Basic log analytics configuration
    sku               = "PerGB2018"
    retention_in_days = 30
    
    # Default network settings
    internet_ingestion_enabled = true
    internet_query_enabled     = true
    
    # No solutions for basic test
    solution_plans = []
    
    # No diagnostic settings for basic test
    diagnostic_settings = []
    
    # No linked storage accounts for basic test
    linked_storage_accounts = {}
    
    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Validate Log Analytics workspace properties
  assert {
    condition     = output.name == "tst-dev-law-eus"
    error_message = "Log Analytics workspace name doesn't match expected value"
  }
  
  assert {
    condition     = length(output.solution_ids) == 0
    error_message = "No solutions should be deployed"
  }
  
  assert {
    condition     = length(output.diagnostic_settings) == 0
    error_message = "No diagnostic settings should be created"
  }
  
  assert {
    condition     = length(output.linked_storage_accounts) == 0
    error_message = "No linked storage accounts should be created"
  }
} 