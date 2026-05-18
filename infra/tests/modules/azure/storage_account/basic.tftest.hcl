/**
 * # Storage Account Module - Basic Test
 * 
 * This test verifies the basic functionality of the storage account module
 * with minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Basic test for storage account creation with minimal configuration
run "basic_storage_account" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"

    # Use auto-generated name based on name components
    name = ""
    name_components = {
      prefix      = "tst"
      environment = "dev"
      region_abbv = "eus"
      instance    = "01"
    }

    # Basic storage account configuration
    account_kind             = "StorageV2"
    account_tier             = "Standard"
    account_replication_type = "LRS"
    access_tier              = "Hot"

    # Default security settings
    min_tls_version                 = "TLS1_2"
    allow_nested_items_to_be_public = false
    shared_access_key_enabled       = true
    blob_public_access_enabled      = false
    public_network_access_enabled   = true

    # No containers, network rules, or private endpoints for basic test
    create_containers = false
    containers        = {} # Empty map instead of empty list

    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/storage_account"
  }

  # Validate storage account properties
  assert {
    condition     = output.name == "tstdeveussa01"
    error_message = "Storage account name doesn't match expected value"
  }

  assert {
    condition     = length(output.containers) == 0
    error_message = "No containers should be created"
  }
} 