/**
 * # Networking Module - Advanced Test
 * 
 * This test verifies advanced functionality of the networking module
 * including AKS-specific networking configuration.
 */

# Variables for Azure provider
variables {
  subscription_id             = "db4f1d99-0ec0-44eb-90de-41975f9bb68b" # Default value
  tenant_id                   = "c945e155-be68-4477-b8d7-01939adbfe55" # Default value
  aks_private_cluster_enabled = true
  aks_node_resource_group     = "MC_test-rg_test-aks_eastus"
  aks_private_dns_zone_id     = null
}

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# Advanced test for networking with AKS configuration
run "advanced_networking" {
  command = plan

  variables {
    # Resource group and location
    resource_group_name = "test-rg"
    location            = "eastus"

    # VNet configuration with multiple address spaces
    vnet_name     = "test-enterprise-vnet"
    address_space = ["10.0.0.0/16", "10.1.0.0/16"]

    # Subnets with advanced configuration
    subnets = {
      "az1-app-subnet" = {
        address_prefixes = ["10.0.0.0/24"]
        service_endpoints = [
          "Microsoft.KeyVault",
          "Microsoft.Storage",
          "Microsoft.Sql"
        ]
        delegation = {}
      },
      "az1-aks-subnet" = {
        address_prefixes = ["10.0.1.0/22"]
        service_endpoints = [
          "Microsoft.KeyVault",
          "Microsoft.Storage",
          "Microsoft.ContainerRegistry",
          "Microsoft.AzureCosmosDB",
          "Microsoft.EventHub"
        ]
        delegation = {}
      },
      "az1-db-subnet" = {
        address_prefixes = ["10.0.5.0/24"]
        service_endpoints = [
          "Microsoft.Sql"
        ]
        delegation = {
          "Microsoft.Sql/managedInstances" = [
            {
              name    = "Microsoft.Sql/managedInstances"
              actions = "Microsoft.Network/virtualNetworks/subnets/join/action"
            }
          ]
        }
      },
      "az1-endpoint-subnet" = {
        address_prefixes  = ["10.0.6.0/24"]
        service_endpoints = []
        delegation        = {}
      }
    }

    # Custom DNS servers
    dns_servers = ["10.0.0.4", "10.0.0.5"]

    # AKS-specific configuration
    enable_aks_networking       = true
    aks_subnet_name             = "az1-aks-subnet"
    aks_cluster_name            = "test-aks"
    aks_private_cluster_enabled = true
    aks_node_resource_group     = "MC_test-rg_test-aks_eastus"
    aks_private_dns_zone_id     = null

    # Comprehensive tagging
    tags = {
      environment   = "production"
      criticality   = "high"
      data-class    = "confidential"
      service-owner = "platform-team"
      cost-center   = "12345"
      application   = "core-infrastructure"
    }
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  # Only validate input variables in plan mode
  assert {
    condition     = var.vnet_name == "test-enterprise-vnet"
    error_message = "VNet name doesn't match expected value"
  }

  assert {
    condition     = length(var.address_space) == 2
    error_message = "VNet should have two address spaces"
  }

  assert {
    condition     = length(var.subnets) == 4
    error_message = "Expected 4 subnets to be created"
  }

  assert {
    condition     = var.aks_subnet_name == "az1-aks-subnet"
    error_message = "AKS subnet name doesn't match expected value"
  }

  assert {
    condition     = var.aks_cluster_name == "test-aks"
    error_message = "AKS cluster name doesn't match expected value"
  }

  assert {
    condition     = var.aks_private_cluster_enabled == true
    error_message = "AKS private cluster should be enabled"
  }

  assert {
    condition     = var.enable_aks_networking == true
    error_message = "AKS networking should be enabled"
  }

  assert {
    condition     = length(var.dns_servers) == 2
    error_message = "Expected 2 DNS servers"
  }
} 