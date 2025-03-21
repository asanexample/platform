provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# ---------------------------------------------------------------------------------------------------------------------
# BASIC NAMING TESTS
# These tests verify basic naming functionality with minimal configuration
# ---------------------------------------------------------------------------------------------------------------------

run "basic_naming_with_customer" {
  command = plan

  variables {
    customer    = "contoso"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify basic resource naming patterns
  assert {
    condition     = output.resource_group == "vip-contoso-dev-rg-eus"
    error_message = "Resource group name does not match expected pattern"
  }

  assert {
    condition     = output.key_vault == "vip-contoso-dev-kv-eus"
    error_message = "Key Vault name does not match expected pattern"
  }

  # Verify special format for storage account (no hyphens, shortened)
  assert {
    condition     = output.storage_account == "vipcontosodevsaeus"
    error_message = "Storage account name does not match expected pattern"
  }

  # Verify that customer is included in appropriate resources
  assert {
    condition     = strcontains(output.workload_identity, "contoso") 
    error_message = "Workload identity should include customer name"
  }

  # Verify normalized customer output
  assert {
    condition     = output.normalized_customer == "contoso"
    error_message = "Normalized customer name should be 'contoso'"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# SHARED RESOURCE NAMING TESTS
# These tests verify naming for shared resources (no customer)
# ---------------------------------------------------------------------------------------------------------------------

run "shared_resource_naming" {
  command = plan

  variables {
    # No customer provided
    environment = "prod"
    region_abbv = "wus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify shared resource naming patterns
  assert {
    condition     = output.virtual_network == "vip-prod-vnet-wus"
    error_message = "Virtual network name does not match expected pattern"
  }

  assert {
    condition     = output.aks_cluster == "vip-prod-aks-wus"
    error_message = "AKS cluster name does not match expected pattern"
  }

  # Verify subnet naming 
  assert {
    condition     = output.subnet_node == "vip-prod-subnet-node-wus"
    error_message = "Node subnet name does not match expected pattern"
  }

  assert {
    condition     = output.subnet_endpoint == "vip-prod-subnet-endpoint-wus"
    error_message = "Endpoint subnet name does not match expected pattern"
  }

  # Verify resource type map is available
  assert {
    condition     = output.resource_types.subnet == "subnet"
    error_message = "Resource type map should include subnet abbreviation"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# COMPLEX NAMING TESTS (SPECIAL CHARACTERS, VALIDATION)
# These tests verify handling of special characters and validation
# ---------------------------------------------------------------------------------------------------------------------

run "complex_naming_tests" {
  command = plan

  variables {
    customer    = "Contoso Corp."  # Contains spaces and punctuation
    environment = "dev"
    region_abbv = "eus2"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify handling of special characters in customer name
  assert {
    condition     = output.storage_account == "vipcontosocorpdevsaeus2"
    error_message = "Storage account should properly normalize customer name"
  }

  # Verify normalized customer has special characters removed
  assert {
    condition     = output.normalized_customer == "contosocorp"
    error_message = "Normalized customer name should have special characters removed"
  }

  # Verify complex resource naming with customer that has special characters
  assert {
    condition     = output.resource_group == "vip-Contoso Corp.-dev-rg-eus2"
    error_message = "Resource group should preserve customer name with special characters"
  }

  # Check names map for complex resources
  assert {
    condition     = lookup(output.names, "cosmos_account", "") != ""
    error_message = "Names map should include cosmos_account"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CUSTOM PREFIX TESTS
# These tests verify custom prefix functionality 
# ---------------------------------------------------------------------------------------------------------------------

run "custom_prefix_tests" {
  command = plan

  variables {
    prefix      = "ctr"
    customer    = "fabrikam"
    environment = "test"
    region_abbv = "neu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Verify custom prefix is used
  assert {
    condition     = output.resource_group == "ctr-fabrikam-test-rg-neu"
    error_message = "Resource group should use custom prefix"
  }

  # Verify storage account with custom prefix
  assert {
    condition     = output.storage_account == "ctrfabrikamtestsaneu"
    error_message = "Storage account should use custom prefix"
  }

  # Verify subnets with custom prefix
  assert {
    condition     = output.subnet_app == "ctr-test-subnet-app-neu"
    error_message = "Subnet should use custom prefix"
  }
} 