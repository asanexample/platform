/**
 * Basic test for the Azure Identities module
 *
 * This test verifies that the module correctly creates a basic AKS identity.
 */

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

run "verify_aks_identity_creation" {
  command = plan

  assert {
    condition     = length(azurerm_user_assigned_identity.aks_identity) == 1
    error_message = "AKS identity should be created when create_aks_identity is true"
  }

  assert {
    condition     = azurerm_user_assigned_identity.aks_identity[0].name == "${var.cluster_name}-identity"
    error_message = "AKS identity name should be derived from cluster name when aks_identity_name is not provided"
  }

  assert {
    condition     = length(azurerm_role_assignment.aks_managed_identity_operator) == 1
    error_message = "Managed Identity Operator role should be assigned to the AKS identity"
  }
} 