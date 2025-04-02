/**
 * # Naming Module - Basic Test
 * 
 * This test verifies the basic functionality of the naming module
 * with standard inputs and default values.
 */

# Basic test of naming patterns with default prefix
run "basic_naming_patterns" {
  command = plan

  variables {
    environment = "dev"
    region_abbv = "weu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify resource group naming pattern
  assert {
    condition     = output.resource_group == "vip-dev-rg-weu"
    error_message = "Resource group naming pattern incorrect"
  }

  # Verify storage account naming pattern (no hyphens)
  assert {
    condition     = output.storage_account == "vipdevsaweu"
    error_message = "Storage account naming pattern incorrect (should have no hyphens)"
  }

  # Verify AKS cluster naming pattern
  assert {
    condition     = output.aks_cluster == "vip-dev-aks-weu"
    error_message = "AKS cluster naming pattern incorrect"
  }

  # Verify key vault naming pattern
  assert {
    condition     = output.key_vault == "vip-dev-kv-weu"
    error_message = "Key vault naming pattern incorrect"
  }
}

# Test with custom prefix
run "custom_prefix_test" {
  command = plan

  variables {
    prefix      = "test"
    environment = "dev"
    region_abbv = "weu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify resource group naming pattern with custom prefix
  assert {
    condition     = output.resource_group == "test-dev-rg-weu"
    error_message = "Resource group naming pattern with custom prefix incorrect"
  }

  # Verify storage account naming pattern with custom prefix
  assert {
    condition     = output.storage_account == "testdevsaweu"
    error_message = "Storage account naming pattern with custom prefix incorrect"
  }
}

# Test with customer name
run "customer_name_test" {
  command = plan

  variables {
    prefix      = "centric"
    customer    = "acme"
    environment = "dev"
    region_abbv = "weu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify resource group naming pattern with customer name
  assert {
    condition     = output.resource_group == "centric-acme-dev-rg-weu"
    error_message = "Resource group naming pattern with customer name incorrect"
  }

  # Verify storage account naming pattern with customer name (normalized)
  assert {
    condition     = output.storage_account == "centricacmedevsaweu"
    error_message = "Storage account naming pattern with customer name incorrect"
  }

  # Verify front door endpoint naming pattern with customer name
  assert {
    condition     = output.frontdoor_endpoint == "centric-acme-dev-fd-endpoint-weu"
    error_message = "Front door endpoint naming pattern with customer name incorrect"
  }
} 