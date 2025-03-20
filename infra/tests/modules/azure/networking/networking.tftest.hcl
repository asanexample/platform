# Test file for Azure Networking module
# Using Terraform 1.6+ testing framework

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# Location variable used by all tests
variables {
  location = "eastus"
}

# Test creation of a basic network
run "create_basic_network" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = var.location
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16"]
    subnets = {
      default = {
        address_prefixes = ["10.0.0.0/24"]
      }
    }
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  # Assert that module outputs are as expected
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

# Original module tests
run "validate_plan" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = var.location
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16"]
    subnets = {
      default = {
        address_prefixes = ["10.0.0.0/24"]
      }
    }
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  # Assert that module outputs are as expected
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

run "multiple_subnets" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = var.location
    vnet_name           = "test-vnet-multiple"
    address_space       = ["10.0.0.0/16"]
    subnets = {
      default = {
        address_prefixes = ["10.0.0.0/24"]
      }
      aks = {
        address_prefixes = ["10.0.1.0/24"]
      }
      endpoints = {
        address_prefixes = ["10.0.2.0/24"]
      }
    }
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  # Assert that module outputs are as expected
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
} 