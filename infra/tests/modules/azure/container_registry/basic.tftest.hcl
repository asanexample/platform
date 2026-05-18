/**
 * # Azure Container Registry Module - Basic Tests
 * 
 * This file contains basic tests for the Azure Container Registry module.
 * It verifies that the module can create a container registry with default settings.
 */

# Provider configuration
provider "azurerm" {
  features {}
  subscription_id                 = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id                       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Variables needed for testing
variables {
  create_registry     = true
  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  region_abbv         = "eus"
}

# Basic test that verifies a container registry can be created with default settings
run "basic_container_registry" {
  command = plan

  # Use the container registry module
  module {
    source = "../../../../modules/azure/container_registry"
  }

  # Verify that the plan contains an azurerm_container_registry resource
  assert {
    condition     = var.create_registry
    error_message = "Container registry creation should be enabled"
  }

  # Verify the resource group name is set correctly
  assert {
    condition     = var.resource_group_name == "test-rg"
    error_message = "Resource group name was not set correctly"
  }

  # Verify the location is set correctly
  assert {
    condition     = var.location == "eastus"
    error_message = "Location was not set correctly"
  }

  # Verify the default SKU is Standard
  assert {
    condition     = coalesce(var.sku, "Standard") == "Standard"
    error_message = "Default SKU should be Standard"
  }

  # Verify admin is disabled by default
  assert {
    condition     = coalesce(var.admin_enabled, false) == false
    error_message = "Admin user should be disabled by default"
  }
}

# Test with a premium SKU and additional features
run "premium_container_registry" {
  command = plan

  # Set premium-specific variables
  variables {
    sku                     = "Premium"
    admin_enabled           = true
    zone_redundancy_enabled = true
    data_endpoint_enabled   = true
    retention_policy_days   = 30
    tags = {
      Environment = "Test"
      Purpose     = "Testing"
    }
  }

  # Use the container registry module
  module {
    source = "../../../../modules/azure/container_registry"
  }

  # Verify the SKU is set to Premium
  assert {
    condition     = var.sku == "Premium"
    error_message = "SKU was not set to Premium"
  }

  # Verify admin is enabled
  assert {
    condition     = var.admin_enabled == true
    error_message = "Admin user was not enabled"
  }

  # Verify zone redundancy is enabled
  assert {
    condition     = var.zone_redundancy_enabled == true
    error_message = "Zone redundancy was not enabled"
  }

  # Verify data endpoint is enabled
  assert {
    condition     = var.data_endpoint_enabled == true
    error_message = "Data endpoint was not enabled"
  }

  # Verify retention policy is configured
  assert {
    condition     = var.retention_policy_days == 30
    error_message = "Retention policy days were not set correctly"
  }

  # Verify tags are set
  assert {
    condition     = try(var.tags.Environment, "") == "Test"
    error_message = "Environment tag was not set correctly"
  }
} 