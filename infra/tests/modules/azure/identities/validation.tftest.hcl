/**
 * # Identities Module - Validation Test
 * 
 * This test verifies validation conditions for the identities module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test prefix validation
run "prefix_validation_test" {
  command = plan

  variables {
    prefix               = "abc"
    customer             = "test"
    environment          = "dev"
    region_abbv          = "eus"
    resource_group_name  = "test-rg"
    location             = "eastus"
    create_aks_identity  = true
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that aks_identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be created with valid prefix"
  }
  
  # Check that the AKS identity has the correct name format with prefix
  assert {
    condition     = can(regex("^abc-dev-aksid-eus$", azurerm_user_assigned_identity.aks_identity[0].name))
    error_message = "AKS identity name should follow the pattern: prefix-env-aksid-region"
  }
}

# Test environment validation - using valid environment
run "environment_validation_test" {
  command = plan

  variables {
    prefix               = "abc"
    customer             = "test"
    environment          = "prod"  # Valid environment (prod, dev, qa)
    region_abbv          = "eus"
    resource_group_name  = "test-rg"
    location             = "eastus"
    create_aks_identity  = true
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that aks_identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be created with valid environment"
  }
  
  # Check that the AKS identity has the correct name format with environment
  assert {
    condition     = can(regex("^abc-prod-aksid-eus$", azurerm_user_assigned_identity.aks_identity[0].name))
    error_message = "AKS identity name should follow the pattern: prefix-env-aksid-region"
  }
}

# Test customer name validation - valid name
run "customer_validation_test" {
  command = plan

  variables {
    prefix               = "abc"
    customer             = "centric"  # Valid customer name (2-10 chars)
    environment          = "dev"
    region_abbv          = "eus"
    resource_group_name  = "test-rg"
    location             = "eastus"
    create_aks_identity  = true
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that aks_identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be created with valid customer name"
  }
  
  # Check that the AKS identity has the correct name format (customer name is in prefix, not in final name)
  assert {
    condition     = can(regex("^abc-dev-aksid-eus$", azurerm_user_assigned_identity.aks_identity[0].name))
    error_message = "AKS identity name should follow the pattern: prefix-env-aksid-region"
  }
}

# Test disabling AKS identity creation
run "disable_aks_identity_test" {
  command = plan

  variables {
    prefix               = "abc"
    customer             = "test"
    environment          = "dev"
    region_abbv          = "eus"
    resource_group_name  = "test-rg"
    location             = "eastus"
    create_aks_identity  = false  # Disable AKS identity creation
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that no aks_identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) == 0
    error_message = "AKS identity should not be created when create_aks_identity is false"
  }
}

# Test workload identity creation - disabled by default
run "workload_identity_disabled_test" {
  command = plan

  variables {
    prefix               = "abc"
    customer             = "test"
    environment          = "dev"
    region_abbv          = "eus"
    resource_group_name  = "test-rg"
    location             = "eastus"
    create_aks_identity  = true
    enable_workload_identity = false  # Default behavior
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that no workload identities are created
  assert {
    condition     = length(azurerm_user_assigned_identity.workload_identities) == 0
    error_message = "No workload identities should be created when enable_workload_identity is false"
  }
}

# Test custom AKS identity name
run "custom_aks_identity_name_test" {
  command = plan

  variables {
    prefix               = "abc"
    customer             = "test"
    environment          = "dev"
    region_abbv          = "eus"
    resource_group_name  = "test-rg"
    location             = "eastus"
    create_aks_identity  = true
    aks_identity_name    = "custom-aks-identity"  # Custom identity name
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that custom aks_identity name is used
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].name == "custom-aks-identity"
    error_message = "AKS identity should use the custom name when provided"
  }
} 