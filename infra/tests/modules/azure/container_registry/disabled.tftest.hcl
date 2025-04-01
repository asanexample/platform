/**
 * # Azure Container Registry Module - Disabled Test
 * 
 * This test verifies that when ACR creation is disabled,
 * no resources are created but the module still functions without errors.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test with ACR creation disabled
run "disabled_acr" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Disable ACR creation for this test
    create_registry = false
    
    # Basic configuration that won't be used
    name        = "testdisabledacr"
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"
    sku         = "Standard"
    
    # Tags
    tags = {
      environment = "test"
      purpose     = "testing-disabled-mode"
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  # Validate that outputs are null when ACR is not created
  assert {
    condition     = output.created == false
    error_message = "The created output should be false when create_registry is false"
  }

  assert {
    condition     = output.id == null
    error_message = "The ID should be null when ACR is not created"
  }

  assert {
    condition     = output.name == null
    error_message = "The name should be null when ACR is not created"
  }

  assert {
    condition     = output.login_server == null
    error_message = "The login_server should be null when ACR is not created"
  }
} 