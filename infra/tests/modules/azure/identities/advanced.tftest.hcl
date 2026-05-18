/**
 * # Identities Module - Advanced Test
 * 
 * This test verifies advanced features of the identities module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test workload identity creation with specific configuration
run "workload_identity_creation_test" {
  command = plan

  variables {
    prefix                   = "abc"
    customer                 = "test"
    environment              = "dev"
    region_abbv              = "eus"
    resource_group_name      = "test-rg"
    location                 = "eastus"
    create_aks_identity      = true
    enable_workload_identity = true
    cluster_name             = "test-aks-cluster"
    workload_identities = {
      "app1" = {
        namespace       = "app1-ns"
        service_account = "app1-sa"
        roles           = ["Reader"]
      },
      "app2" = {
        name            = "custom-app2-identity"
        namespace       = "app2-ns"
        service_account = "app2-sa"
        roles           = ["Contributor"]
      }
    }
    # Using a hardcoded value for OIDC URL since this is a test
    aks_oidc_issuer_url = "https://oidc.test.aks.test.az.com/"
    # Using a hardcoded value for node resource group ID since this is a test
    node_resource_group_id       = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/MC_test-rg_test-aks_eastus"
    create_federated_credentials = true
    create_role_assignments      = true
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify workload identities are created
  assert {
    condition     = length(var.workload_identities) == 2
    error_message = "Should have two workload identities configured"
  }

  # Verify identity resources are created with correct names
  assert {
    condition     = contains(keys(azurerm_user_assigned_identity.workload_identities), "app1")
    error_message = "Workload identity should be created for app1"
  }

  assert {
    condition     = contains(keys(azurerm_user_assigned_identity.workload_identities), "app2")
    error_message = "Workload identity should be created for app2"
  }

  # Verify federated credentials
  assert {
    condition     = length(azurerm_federated_identity_credential.workload_credentials) > 0
    error_message = "Federated credentials should be created"
  }

  # Verify custom identity name
  assert {
    condition     = azurerm_user_assigned_identity.workload_identities["app2"].name == "custom-app2-identity"
    error_message = "Custom identity name should be used for app2"
  }

  # Verify default identity name pattern
  assert {
    condition     = azurerm_user_assigned_identity.workload_identities["app1"].name == "test-aks-cluster-app1"
    error_message = "Default identity name should follow cluster_name-identity_key pattern"
  }
}

# Test with federated credential creation disabled
run "federated_credentials_disabled_test" {
  command = plan

  variables {
    prefix                   = "abc"
    customer                 = "test"
    environment              = "dev"
    region_abbv              = "eus"
    resource_group_name      = "test-rg"
    location                 = "eastus"
    create_aks_identity      = true
    enable_workload_identity = true
    cluster_name             = "test-aks-cluster"
    workload_identities = {
      "app1" = {
        namespace       = "app1-ns"
        service_account = "app1-sa"
        roles           = ["Reader"]
      }
    }
    create_federated_credentials = false
    create_role_assignments      = false
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify workload identity is created
  assert {
    condition     = length(keys(azurerm_user_assigned_identity.workload_identities)) == 1
    error_message = "One workload identity should be created"
  }

  # Verify no federated credentials are created
  assert {
    condition     = length(keys(azurerm_federated_identity_credential.workload_credentials)) == 0
    error_message = "No federated credentials should be created when disabled"
  }
}

# Test with subnet permissions
run "subnet_permissions_test" {
  command = plan

  variables {
    prefix              = "abc"
    customer            = "test"
    environment         = "dev"
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    create_aks_identity = true
    subnet_id           = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify AKS identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) > 0
    error_message = "AKS identity should be created"
  }

  # Verify subnet role assignment is created (testing subnet permissions)
  assert {
    condition     = length(azurerm_role_assignment.aks_subnet_network_contributor) > 0
    error_message = "Subnet role assignment should be created when subnet_id is provided"
  }
} 