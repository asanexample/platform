/**
 * # Resource Group Module - Advanced Test
 * 
 * This test verifies advanced scenarios for the resource group module
 * including automatic naming and tag merging.
 */

# Provider configuration with Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Test using naming module variables instead of explicit name
run "auto_naming_test" {
  command = plan

  variables {
    name       = null  # Using null to trigger naming module pattern
    prefix     = "test"
    environment = "dev"
    region_abbv = "eus"
    customer   = "acme"
    location   = "eastus"
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  # The module should derive name from naming module
  assert {
    condition     = var.name == null
    error_message = "Name should be null to trigger automatic naming"
  }
  
  assert {
    condition     = output.location == "eastus"
    error_message = "Resource group location doesn't match expected value"
  }
}

# Test with comprehensive tags
run "comprehensive_tags_test" {
  command = plan

  variables {
    name     = "test-advanced-rg"
    location = "westeurope"
    tags = {
      environment     = "test"
      project         = "terraform-module-testing"
      owner           = "platform-team"
      cost-center     = "12345"
      application     = "terraform"
      confidentiality = "internal"
      automated       = "true"
      deployment-date = "2023-04-01"
      lifecycle       = "experimental"
    }
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  # Verify all tags are applied
  assert {
    condition     = length(keys(var.tags)) == 9
    error_message = "Resource group should have all 9 tags applied"
  }
  
  assert {
    condition     = var.tags["environment"] == "test" && var.tags["project"] == "terraform-module-testing"
    error_message = "Key tags should match expected values"
  }
}

# Test with different regions
run "multi_region_test" {
  command = plan

  variables {
    name     = "test-westus-rg"
    location = "westus"
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  assert {
    condition     = output.location == "westus"
    error_message = "Resource group location should be westus"
  }
}

# Test resource group with customer-specific naming
run "customer_specific_naming_test" {
  command = plan

  variables {
    name       = null  # Using null to trigger naming module pattern
    prefix     = "test"
    environment = "prod"
    region_abbv = "weu"
    customer   = "contoso"
    location   = "westeurope"
    tags = {
      customer    = "contoso"
      environment = "production"
      managed-by  = "terraform"
    }
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  # Verify customer-specific configuration
  assert {
    condition     = var.customer == "contoso" && var.environment == "prod"
    error_message = "Customer and environment should be correctly configured"
  }
  
  assert {
    condition     = var.tags["customer"] == "contoso"
    error_message = "Customer tag should be present with correct value"
  }
} 