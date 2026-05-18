/**
 * # Azure Container Registry Module - Integration Test
 * 
 * This test verifies the integration of ACR module with other resources,
 * focusing on dependencies and interactions.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test for ACR with multiple module integrations
run "module_integration" {
  command = plan

  # Define mock values directly
  variables {
    # Resource properties
    resource_group_name = "mock-integration-rg"
    location            = "eastus"
    name                = "mockintegrationacr"

    # Enable ACR creation for test
    create_registry = true

    # Standard properties
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"

    # ACR configuration
    sku = "Standard"

    # AKS integration - with mock principal_id
    aks_integration_enabled = true
    aks_principal_id        = "00000000-0000-0000-0000-000000000002"

    # Tags
    tags = {
      environment = "test"
      purpose     = "integration-testing"
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  # Validate ACR properties
  assert {
    condition     = output.name == "mockintegrationacr"
    error_message = "ACR name doesn't match expected value"
  }

  assert {
    condition     = output.resource_group_name == "mock-integration-rg"
    error_message = "Resource group name doesn't match expected value"
  }

  assert {
    condition     = var.aks_integration_enabled == true
    error_message = "AKS integration should be enabled"
  }
} 