# Test file for Azure networking module
# Using Terraform 1.6+ testing framework

# Define variables for the test
variables {
  resource_group_name = "test-rg"
  location            = "eastus"
  vnet_name           = "test-vnet"
  address_space       = ["10.0.0.0/16"]
  
  subnets = {
    "test-subnet" = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
  
  tags = {
    Environment = "test"
    ManagedBy   = "Terraform"
  }
}

# First run block - validate the plan without creating resources
run "validate_plan" {
  command = plan

  # Assert that the virtual network has the correct name
  assert {
    condition     = azurerm_virtual_network.vnet.name == "test-vnet"
    error_message = "VNet name does not match expected value"
  }
  
  # Assert that the VNet has the correct address space
  assert {
    condition     = contains(azurerm_virtual_network.vnet.address_space, "10.0.0.0/16")
    error_message = "VNet address space does not contain expected value"
  }
  
  # Assert that the subnet has the correct address prefix
  assert {
    condition     = contains(azurerm_subnet.subnet["test-subnet"].address_prefixes, "10.0.1.0/24")
    error_message = "Subnet address prefix does not match expected value"
  }
  
  # Assert that tags are correctly applied
  assert {
    condition     = azurerm_virtual_network.vnet.tags["Environment"] == "test"
    error_message = "VNet tags do not match expected values"
  }
  
  # Assert that the NSG has the correct name
  assert {
    condition     = azurerm_network_security_group.nsg["test-subnet"].name == "test-subnet-nsg"
    error_message = "NSG name does not match expected value"
  }
}

# Second run block - testing different subnet configurations
run "multiple_subnets" {
  command = plan
  
  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    vnet_name           = "test-vnet"
    address_space       = ["10.0.0.0/16"]
    
    subnets = {
      "app-subnet" = {
        address_prefixes  = ["10.0.1.0/24"]
        service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      },
      "data-subnet" = {
        address_prefixes  = ["10.0.2.0/24"]
        service_endpoints = ["Microsoft.Sql"]
      }
    }
  }
  
  # Assert that both subnets are created
  assert {
    condition     = length(azurerm_subnet.subnet) == 2
    error_message = "Expected 2 subnets to be created"
  }
  
  # Assert that the app subnet has the correct service endpoints
  assert {
    condition     = contains(azurerm_subnet.subnet["app-subnet"].service_endpoints, "Microsoft.KeyVault")
    error_message = "App subnet does not have expected service endpoints"
  }
  
  # Assert that NSGs are created for both subnets
  assert {
    condition     = length(azurerm_network_security_group.nsg) == 2
    error_message = "Expected 2 NSGs to be created"
  }
} 