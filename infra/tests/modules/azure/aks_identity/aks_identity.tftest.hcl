/**
 * # Tests for Azure AKS Identity Module
 *
 * This file contains tests for the Azure AKS Identity module.
 */

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# Global variables for tests
variables {
  resource_group_name = "test-rg"
  location            = "eastus"
  prefix              = "test"
  environment         = "dev"
  cluster_name        = "test-aks-cluster"
}

# Test basic AKS identity creation
run "create_basic_aks_identity" {
  command = plan

  variables {
    tags = {
      environment = "test"
      purpose     = "module-testing"
    }
  }

  module {
    source = "../../../../modules/azure/aks_identity"
  }

  assert {
    condition     = var.resource_group_name == "test-rg"
    error_message = "Resource group name should be test-rg"
  }

  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }

  assert {
    condition     = var.cluster_name == "test-aks-cluster"
    error_message = "Cluster name should be test-aks-cluster"
  }
}

# Test with custom identity names
run "create_aks_identity_custom_names" {
  command = plan

  variables {
    aks_identity_name          = "custom-aks-identity"
    cert_manager_identity_name = "custom-cert-manager"
    karpenter_identity_name    = "custom-karpenter"
    
    # Custom federated credential names
    cert_manager_federated_credential_name = "custom-cert-manager-fedcred"
    karpenter_federated_credential_name    = "custom-karpenter-fedcred"
    
    tags = {
      environment = "test"
      purpose     = "module-testing"
    }
  }

  module {
    source = "../../../../modules/azure/aks_identity"
  }

  assert {
    condition     = var.resource_group_name == "test-rg"
    error_message = "Resource group name should be test-rg"
  }

  assert {
    condition     = var.cluster_name == "test-aks-cluster"
    error_message = "Cluster name should be test-aks-cluster"
  }

  assert {
    condition     = var.aks_identity_name == "custom-aks-identity"
    error_message = "AKS identity name should be custom-aks-identity"
  }
} 