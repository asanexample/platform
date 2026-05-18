/**
 * # Resource Group Module - Validation Test
 * 
 * This test verifies that the resource group module correctly validates input variables
 * and handles edge cases appropriately.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test with valid values at the edge of allowed ranges
run "valid_edge_case_values" {
  command = plan

  variables {
    # Name with valid length (89 chars, within 90 char limit)
    name     = "a-very-long-resource-group-name-that-is-89-characters-long-for-testing-purposes-only-x"
    location = "eastus"
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  assert {
    condition     = output.name == "a-very-long-resource-group-name-that-is-89-characters-long-for-testing-purposes-only-x"
    error_message = "Resource group with maximum length name failed"
  }
}

# Test with valid special characters in name
run "valid_name_with_special_chars" {
  command = plan

  variables {
    name     = "test-rg_with.special(chars)"
    location = "eastus"
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  assert {
    condition     = output.name == "test-rg_with.special(chars)"
    error_message = "Resource group with special characters in name failed"
  }
}

# Test with valid but less common Azure regions
run "valid_uncommon_regions" {
  command = plan

  variables {
    name     = "test-rg"
    location = "qatarcentral"
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  assert {
    condition     = output.location == "qatarcentral"
    error_message = "Resource group creation in uncommon region failed"
  }
} 