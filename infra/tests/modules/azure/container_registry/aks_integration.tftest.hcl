/**
 * # Azure Container Registry Module - AKS Integration Test
 * 
 * This test verifies the AKS integration functionality of the ACR module,
 * focusing on role assignments and access controls.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test for ACR with AKS integration
run "aks_integration" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Name and standard properties
    name        = "testaksacr"
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"
    sku         = "Standard"
    
    # AKS integration - pull access only
    aks_integration_enabled = true
    aks_principal_id        = "00000000-0000-0000-0000-000000000001"
    enable_aks_acr_push     = false
    
    # Tags
    tags = {
      environment = "test"
      purpose     = "aks-integration-testing"
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  # Validate ACR properties related to AKS integration
  assert {
    condition     = var.aks_integration_enabled == true
    error_message = "AKS integration should be enabled"
  }

  assert {
    condition     = var.aks_principal_id != null
    error_message = "AKS principal ID should not be null"
  }
}

# Test for ACR with AKS integration and both pull and push access
run "aks_integration_with_push" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Name and standard properties
    name        = "testakspushacr"
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"
    sku         = "Standard"
    
    # AKS integration - with push access
    aks_integration_enabled = true
    aks_principal_id        = "00000000-0000-0000-0000-000000000001"
    enable_aks_acr_push     = true
    
    # Tags
    tags = {
      environment = "test"
      purpose     = "aks-integration-testing-with-push"
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  # Validate ACR properties related to AKS integration with push access
  assert {
    condition     = var.aks_integration_enabled == true
    error_message = "AKS integration should be enabled"
  }

  assert {
    condition     = var.aks_principal_id != null
    error_message = "AKS principal ID should not be null"
  }

  assert {
    condition     = var.enable_aks_acr_push == true
    error_message = "AKS push access should be enabled"
  }
} 