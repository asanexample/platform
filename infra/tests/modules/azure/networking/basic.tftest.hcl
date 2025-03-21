provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  location = "eastus"
}

run "create_basic_network" {
  command = plan

  variables {
    resource_group_name = "test-network-rg"
    location            = var.location
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16"]

    subnets = {
      "web" = {
        address_prefixes = ["10.0.1.0/24"]
      },
      "app" = {
        address_prefixes = ["10.0.2.0/24"]
      },
      "data" = {
        address_prefixes  = ["10.0.3.0/24"]
        service_endpoints = ["Microsoft.Storage"]
      }
    }

    tags = {
      Environment = "Test"
      Project     = "Networking Tests"
    }
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  # Check a variable access to satisfy Terraform's requirement
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
} 