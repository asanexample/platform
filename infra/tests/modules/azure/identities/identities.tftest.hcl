provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# ---------------------------------------------------------------------------------------------------------------------
# BASIC AKS IDENTITY TESTS
# These tests verify the module correctly creates a basic AKS identity
# ---------------------------------------------------------------------------------------------------------------------

run "basic_aks_identity" {
  command = plan

  variables {
    prefix      = "test"
    customer    = "example"
    stage       = "dev"
    region_abbv = "eus"
    
    resource_group_name = "test-identities-rg"
    location            = "eastus"
    cluster_name        = "test-aks-cluster"
    create_aks_identity = true
    
    tags = {
      Environment = "Test"
      Terraform   = "True"
    }
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify AKS identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) == 1
    error_message = "AKS identity should be created when create_aks_identity is true"
  }

  # Verify AKS identity name
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].name == "test-aks-cluster-identity"
    error_message = "AKS identity name should be derived from cluster name when aks_identity_name is not provided"
  }

  # Verify role assignments
  assert {
    condition     = length(azurerm_role_assignment.aks_managed_identity_operator) == 1
    error_message = "Managed Identity Operator role should be assigned to the AKS identity"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# WORKLOAD IDENTITY TESTS
# These tests verify the module correctly creates workload identities
# ---------------------------------------------------------------------------------------------------------------------

run "workload_identities" {
  command = plan

  variables {
    prefix      = "test"
    customer    = "example"
    stage       = "dev"
    region_abbv = "eus"
    
    resource_group_name = "test-identities-rg"
    location            = "eastus"
    cluster_name        = "test-aks-cluster"
    create_aks_identity = true
    
    # Workload identity configuration
    enable_workload_identity = true
    create_federated_credentials = true
    create_role_assignments = true
    aks_oidc_issuer_url      = "https://eastus.oic.prod-aks.azure.com/12345678-1234-1234-1234-1234567890ab/abcdef1234567890/"
    node_resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MC_test-identities-rg_test-aks-cluster_eastus"
    
    # Define workload identities
    workload_identities = {
      "cert-manager" = {
        namespace       = "cert-manager"
        service_account = "cert-manager"
        roles           = ["DNS Zone Contributor"]
      },
      "karpenter" = {
        namespace       = "karpenter"
        service_account = "karpenter"
        roles           = ["Virtual Machine Contributor", "Network Contributor"]
      }
    }
    
    tags = {
      Environment = "Test"
      Terraform   = "True"
    }
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify AKS identity is created
  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) == 1
    error_message = "AKS identity should be created when create_aks_identity is true"
  }

  # Verify workload identities are created
  assert {
    condition     = length(azurerm_user_assigned_identity.workload_identities) == 2
    error_message = "Both workload identities should be created"
  }

  # Verify cert-manager identity is created
  assert {
    condition     = contains(keys(azurerm_user_assigned_identity.workload_identities), "cert-manager")
    error_message = "cert-manager identity should be created"
  }

  # Verify karpenter identity is created
  assert {
    condition     = contains(keys(azurerm_user_assigned_identity.workload_identities), "karpenter")
    error_message = "karpenter identity should be created"
  }

  # Verify federated credentials are created
  assert {
    condition     = length(azurerm_federated_identity_credential.workload_credentials) == 2
    error_message = "Federated identity credentials should be created for both workload identities"
  }

  # Verify role assignments for node resource group
  assert {
    condition     = length(azurerm_role_assignment.workload_node_rg_roles) == 3
    error_message = "Role assignments should be created for workload identities on node resource group"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CUSTOM IDENTITY NAME TESTS
# These tests verify custom identity naming functionality
# ---------------------------------------------------------------------------------------------------------------------

run "custom_identity_name" {
  command = plan

  variables {
    prefix      = "test"
    customer    = "example"
    stage       = "dev"
    region_abbv = "eus"
    
    resource_group_name = "test-identities-rg"
    location            = "eastus"
    cluster_name        = "test-aks-cluster"
    create_aks_identity = true
    aks_identity_name   = "my-custom-identity"
    
    tags = {
      Environment = "Test"
      Terraform   = "True"
    }
  }

  module {
    source = "../../../../modules/azure/identities"
  }

  # Verify AKS identity name uses custom name
  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].name == "my-custom-identity"
    error_message = "AKS identity should use the custom name provided"
  }
} 