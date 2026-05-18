/**
 * # Networking Module - Basic Test
 * 
 * This test verifies the basic functionality of the networking module
 * with minimal configuration.
 */

# Variables for Azure provider
variables {
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b" # Default value
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55" # Default value
}

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# Basic test for networking with minimal configuration
run "basic_networking" {
  command = plan

  variables {
    # Resource group and location
    resource_group_name = "test-rg"
    location            = "eastus"

    # VNet configuration
    vnet_name     = "test-vnet"
    address_space = ["10.0.0.0/16"]

    # Subnets
    subnets = {
      "default-subnet" = {
        address_prefixes = ["10.0.0.0/24"]
        service_endpoints = [
          "Microsoft.KeyVault",
          "Microsoft.Storage"
        ]
        delegation = {}
      },
      "aks-subnet" = {
        address_prefixes = ["10.0.1.0/24"]
        service_endpoints = [
          "Microsoft.KeyVault",
          "Microsoft.Storage",
          "Microsoft.ContainerRegistry"
        ]
        delegation = {}
      }
    }

    # No custom DNS servers for basic test
    dns_servers = []

    # No AKS-specific configuration for basic test
    enable_aks_networking = false
    aks_subnet_name       = null
    aks_cluster_name      = null

    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  # Only validate input variables in plan mode
  assert {
    condition     = var.vnet_name == "test-vnet"
    error_message = "VNet name doesn't match expected value"
  }

  assert {
    condition     = var.address_space[0] == "10.0.0.0/16"
    error_message = "VNet address space doesn't match expected value"
  }

  assert {
    condition     = length(var.subnets) == 2
    error_message = "Expected 2 subnets to be defined"
  }

  assert {
    condition     = contains(keys(var.subnets), "default-subnet")
    error_message = "Default subnet should be defined"
  }

  assert {
    condition     = contains(keys(var.subnets), "aks-subnet")
    error_message = "AKS subnet should be defined"
  }

  assert {
    condition     = var.enable_aks_networking == false
    error_message = "AKS networking should be disabled"
  }

  assert {
    condition     = var.aks_subnet_name == null
    error_message = "AKS subnet name should be null"
  }
} 