/**
 * # Identities Module - Basic Test
 * 
 * This test verifies the basic functionality of the identities module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test basic identity creation
run "basic_identity_creation" {
  command = plan

  variables {
    workload            = "platform"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    create_aks_identity = true
    tags = {
      environment = "dev"
      application = "testing"
      owner       = "terraform"
    }
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that aks_identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be created"
  }

  # Check that the AKS identity has the correct name format
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].name == "aksid-platform-dev-weu"
    error_message = "AKS identity name should follow CAF pattern: aksid-{workload}-{env}-{region}"
  }

  # Check that the identity has the correct tags (including the name tag added by the module)
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity[0].tags) == 4
    error_message = "AKS identity should have 4 tags (3 provided + name tag added by module)"
  }

  # Check that the identity is in the right resource group
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].resource_group_name == "test-rg"
    error_message = "AKS identity should be created in the specified resource group"
  }

  # Check that the identity is in the right location
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].location == "westeurope"
    error_message = "AKS identity should be created in the specified location"
  }
}

# Test enabling workload identity feature
run "workload_identity_enabled_test" {
  command = plan

  variables {
    workload                 = "platform"
    environment              = "dev"
    region_abbv              = "weu"
    resource_group_name      = "test-rg"
    location                 = "westeurope"
    create_aks_identity      = true
    enable_workload_identity = true
    cluster_name             = "aks-test-cluster"
    workload_identities = {
      workload1 = {
        namespace       = "default"
        service_account = "workload1-sa"
        roles           = ["Reader"]
      },
      workload2 = {
        namespace       = "kube-system"
        service_account = "workload2-sa"
        roles           = ["Contributor"]
      }
    }
    tags = {
      environment = "dev"
      application = "testing"
      owner       = "terraform"
    }
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Check that aks_identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be created"
  }

  # Check that workload identities are created
  assert {
    condition     = length(azurerm_user_assigned_identity.workload_identities) == 2
    error_message = "Two workload identities should be created"
  }

  # Check first workload identity
  assert {
    condition     = contains(keys(azurerm_user_assigned_identity.workload_identities), "workload1")
    error_message = "Workload1 identity should be created"
  }

  # Check second workload identity
  assert {
    condition     = contains(keys(azurerm_user_assigned_identity.workload_identities), "workload2")
    error_message = "Workload2 identity should be created"
  }
} 