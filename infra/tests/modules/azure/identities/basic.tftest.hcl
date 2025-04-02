/**
 * # Azure Identities Module - Basic Test
 * 
 * This test verifies the basic functionality of the Azure Identities module
 * with minimal configuration.
 */

# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Basic test with minimal configuration
run "basic_identity_creation" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    create_aks_identity = true
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify AKS identity is planned for creation
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be planned for creation"
  }

  # Verify identity name format
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].name == "centric-dev-weu-aks-id"
    error_message = "AKS identity name should follow the pattern from the naming module"
  }

  # Verify the resource group and location are set correctly
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].resource_group_name == "test-rg"
    error_message = "AKS identity should use the specified resource group"
  }

  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].location == "westeurope"
    error_message = "AKS identity should use the specified location"
  }
}

# Test with custom identity name
run "custom_identity_name" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    create_aks_identity = true
    aks_identity_name   = "custom-aks-identity"
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify custom identity name is used
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].name == "custom-aks-identity"
    error_message = "Custom AKS identity name should be used when specified"
  }
}

# Test with identity creation disabled
run "identity_creation_disabled" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    create_aks_identity = false
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify no identity is created when disabled
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) == 0
    error_message = "No AKS identity should be planned when creation is disabled"
  }
} 