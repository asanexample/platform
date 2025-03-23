/**
 * # Azure Container Registry Module - Basic Test
 * 
 * This test verifies the basic functionality of the ACR module
 * with standard configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Variables for Azure credentials passed via environment variables
variables {
  subscription_id = ""
  tenant_id = ""
}

# Basic test for ACR creation with standard configuration
run "basic_acr" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Use auto-generated name
    name        = null
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"
    
    # Standard SKU
    sku = "Standard"
    
    # Default settings
    admin_enabled                 = false
    public_network_access_enabled = true
    
    # No AKS integration for basic test
    aks_integration_enabled = false
    aks_principal_id        = null
    
    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  # Validate ACR properties
  assert {
    condition     = output.name == "testdevacreus"
    error_message = "ACR name doesn't match expected value"
  }

  assert {
    condition     = output.sku == "Standard"
    error_message = "SKU doesn't match expected value"
  }

  assert {
    condition     = output.admin_enabled == false
    error_message = "Admin enabled doesn't match expected value"
  }

  assert {
    condition     = output.public_network_access_enabled == true
    error_message = "Public network access doesn't match expected value"
  }

  assert {
    condition     = output.location == "eastus"
    error_message = "Location doesn't match expected value"
  }
} 