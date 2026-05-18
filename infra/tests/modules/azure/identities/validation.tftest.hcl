/**
 * # Identities Module - Validation Test
 *
 * This test verifies validation conditions for the identities module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test workload validation
run "workload_validation_test" {
  command = plan

  variables {
    workload            = "platform"
    environment         = "dev"
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    create_aks_identity = true
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that aks_identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be created with valid workload"
  }

  # Check that the AKS identity has the correct CAF name format
  assert {
    condition     = can(regex("^aksid-platform-dev-eus$", azurerm_user_assigned_identity.aks_identity[0].name))
    error_message = "AKS identity name should follow CAF pattern: aksid-{workload}-{env}-{region}"
  }
}

# Test environment validation - using valid environment
run "environment_validation_test" {
  command = plan

  variables {
    workload            = "platform"
    environment         = "prod"
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    create_aks_identity = true
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
    condition     = can(regex("^aksid-platform-prod-eus$", azurerm_user_assigned_identity.aks_identity[0].name))
    error_message = "AKS identity name should follow CAF pattern: aksid-{workload}-{env}-{region}"
  }
}

# Test different workload name
run "workload_variation_test" {
  command = plan

  variables {
    workload            = "hipaa"
    environment         = "dev"
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    create_aks_identity = true
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that aks_identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be created with valid workload name"
  }

  # Check that the AKS identity has the correct name format
  assert {
    condition     = can(regex("^aksid-hipaa-dev-eus$", azurerm_user_assigned_identity.aks_identity[0].name))
    error_message = "AKS identity name should follow CAF pattern: aksid-{workload}-{env}-{region}"
  }
}

# Test disabling AKS identity creation
run "disable_aks_identity_test" {
  command = plan

  variables {
    workload            = "platform"
    environment         = "dev"
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    create_aks_identity = false
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
    workload                 = "platform"
    environment              = "dev"
    region_abbv              = "eus"
    resource_group_name      = "test-rg"
    location                 = "eastus"
    create_aks_identity      = true
    enable_workload_identity = false
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
    workload            = "platform"
    environment         = "dev"
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    create_aks_identity = true
    aks_identity_name   = "custom-aks-identity"
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
