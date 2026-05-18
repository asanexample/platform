/**
 * # Key Vault Module - Basic Test
 * 
 * This test verifies the basic functionality of the Key Vault module
 * with minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Basic test for key vault with minimal configuration
run "basic_key_vault" {
  command = plan

  variables {
    name                = "testkv23097"
    resource_group_name = "test-rg"
    location            = "eastus"
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  # Validate key vault properties
  assert {
    condition     = output.name == "testkv23097"
    error_message = "Key vault name doesn't match expected value"
  }
} 