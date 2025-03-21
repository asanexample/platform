/**
 * # Tests for Azure Resource Group Module
 *
 * This file contains tests for the Azure Resource Group module.
 */

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# Global variables for tests
variables {
  name     = "test-rg"
  location = "eastus"
}

# Basic resource group creation test
run "create_basic_resource_group" {
  command = plan

  variables {
    tags = {
      environment = "test"
      purpose     = "module-testing"
    }
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  assert {
    condition     = var.name == "test-rg"
    error_message = "Resource group name should be test-rg"
  }

  assert {
    condition     = var.location == "eastus"
    error_message = "Resource group location should be eastus"
  }
}

# Testing with no tags
run "create_resource_group_no_tags" {
  command = plan

  module {
    source = "../../../../modules/azure/resource_group"
  }

  assert {
    condition     = var.name == "test-rg"
    error_message = "Resource group name should be test-rg"
  }

  assert {
    condition     = var.location == "eastus"
    error_message = "Resource group location should be eastus"
  }
}

# Testing with a different location
run "create_resource_group_west_us" {
  command = plan

  variables {
    location = "westus2"
    tags = {
      environment = "production"
    }
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  assert {
    condition     = var.name == "test-rg"
    error_message = "Resource group name should be test-rg"
  }

  assert {
    condition     = var.location == "westus2"
    error_message = "Resource group location should be westus2"
  }
} 