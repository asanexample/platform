/**
 * # Networking Module - Validation Test
 * 
 * This test verifies validation conditions for the networking module.
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

# Test valid vnet name
run "vnet_name_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    vnet_name           = "test-vnet-2" # Valid with alphanumeric and hyphen
    address_space       = ["10.0.0.0/16"]
    subnets = {
      "default" = {
        address_prefixes = ["10.0.0.0/24"]
      }
    }
    tags = {}
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  assert {
    condition     = output.vnet_name == "test-vnet-2"
    error_message = "VNet name validation should pass"
  }
}

# Test valid address space
run "address_space_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16", "172.16.0.0/12"] # Multiple valid CIDRs
    subnets = {
      "default" = {
        address_prefixes = ["10.0.0.0/24"]
      }
    }
    tags = {}
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  assert {
    condition     = length(output.vnet_address_space) == 2
    error_message = "Multiple address spaces should be allowed"
  }
}

# Test valid subnet naming and CIDR
run "subnet_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16"]
    subnets = {
      "app-subnet" = {
        address_prefixes = ["10.0.0.0/24"]
      },
      "db-subnet" = {
        address_prefixes = ["10.0.1.0/24"]
      },
      "aks-subnet" = {
        address_prefixes = ["10.0.2.0/23"] # Larger subnet size
      }
    }
    tags = {}
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  assert {
    condition     = length(output.subnet_ids) == 3
    error_message = "All three subnets should be created"
  }
}

# Test valid service endpoints
run "service_endpoints_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16"]
    subnets = {
      "default" = {
        address_prefixes = ["10.0.0.0/24"]
        service_endpoints = [
          "Microsoft.KeyVault",
          "Microsoft.Storage",
          "Microsoft.Sql",
          "Microsoft.AzureCosmosDB",
          "Microsoft.Web"
        ]
      }
    }
    tags = {}
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  assert {
    condition     = length(output.subnet_ids) == 1
    error_message = "Subnet with multiple service endpoints should be created"
  }
}

# Test valid delegation
run "delegation_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16"]
    subnets = {
      "app-service-subnet" = {
        address_prefixes = ["10.0.0.0/24"]
        delegation = {
          "Microsoft.Web/serverFarms" = [
            {
              name    = "Microsoft.Web/serverFarms"
              actions = "Microsoft.Network/virtualNetworks/subnets/action"
            }
          ]
        }
      }
    }
    tags = {}
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  assert {
    condition     = length(output.subnet_ids) == 1
    error_message = "Subnet with delegation should be created"
  }
}

# Test valid DNS servers
run "dns_servers_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16"]
    subnets = {
      "default" = {
        address_prefixes = ["10.0.0.0/24"]
      }
    }
    dns_servers = ["192.168.1.1", "192.168.1.2"] # Valid DNS servers
    tags        = {}
  }

  module {
    source = "../../../../modules/azure/networking"
  }

  assert {
    condition     = output.vnet_name == "test-vnet"
    error_message = "VNet with valid DNS servers should be created"
  }
} 