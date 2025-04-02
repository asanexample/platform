/**
 * # Naming Module - Advanced Test
 * 
 * This test verifies the advanced functionality of the naming module
 * focusing on edge cases, special characters, and length constraints.
 */

# Test with special characters in customer name
run "special_characters_test" {
  command = plan

  variables {
    prefix      = "test"
    customer    = "acme-corp"  # Contains special character
    environment = "dev"
    region_abbv = "weu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify storage account naming pattern handles special characters correctly
  assert {
    condition     = output.storage_account == "testacmecorpdevsaweu"
    error_message = "Storage account naming should normalize special characters"
  }

  # Verify container registry naming pattern handles special characters correctly
  assert {
    condition     = output.container_registry == "testacmecorpdevacrweu"
    error_message = "Container registry naming should normalize special characters"
  }
}

# Test with long customer name (length constraints)
run "long_customer_name_test" {
  command = plan

  variables {
    prefix      = "test"
    customer    = "verylongcustomername"  # Long customer name
    environment = "dev"
    region_abbv = "weu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify storage account naming pattern handles long names 
  # Storage accounts have a 24 character limit
  assert {
    condition     = length(output.storage_account) <= 24
    error_message = "Storage account name should not exceed 24 characters"
  }

  # Verify key vault naming pattern handles long names
  # Key vaults have a 24 character limit
  assert {
    condition     = length(output.key_vault) <= 24
    error_message = "Key vault name should not exceed 24 characters"
  }
}

# Test with different environment values
run "different_environment_test" {
  command = plan

  variables {
    prefix      = "test"
    environment = "prod"
    region_abbv = "weu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify resource group naming pattern with production environment
  assert {
    condition     = output.resource_group == "test-prod-rg-weu"
    error_message = "Resource group naming with production environment incorrect"
  }

  # Verify storage account naming pattern with production environment
  assert {
    condition     = output.storage_account == "testprodsaweu"
    error_message = "Storage account naming with production environment incorrect"
  }
}

# Test with different region values
run "different_region_test" {
  command = plan

  variables {
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"  # East US
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify resource group naming pattern with different region
  assert {
    condition     = output.resource_group == "test-dev-rg-eus"
    error_message = "Resource group naming with East US region incorrect"
  }

  # Verify storage account naming pattern with different region
  assert {
    condition     = output.storage_account == "testdevsaeus"
    error_message = "Storage account naming with East US region incorrect"
  }
}

# Test for format compliance with special resource types
run "format_compliance_test" {
  command = plan

  variables {
    prefix      = "vip"
    environment = "dev"
    region_abbv = "weu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify AKS node pool name format compliance (12 char limit, alphanumeric only)
  assert {
    condition     = length(output.aks_node_pool) <= 12 && can(regex("^[a-z0-9]+$", output.aks_node_pool))
    error_message = "AKS node pool name should meet format requirements"
  }

  # Verify managed Prometheus name format compliance
  assert {
    condition     = can(regex("^[a-zA-Z0-9\\-_]+$", output.managed_prometheus))
    error_message = "Managed Prometheus name should meet format requirements"
  }
} 