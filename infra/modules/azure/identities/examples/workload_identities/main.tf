/**
 * # Workload Identities Example for Azure Identities Module
 *
 * This example shows how to create workload identities for an AKS cluster.
 */

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

resource "azurerm_resource_group" "test" {
  name     = "test-workload-identities-rg"
  location = "eastus"
}

# Simulate an OIDC issuer URL as it would come from an AKS cluster
locals {
  mock_oidc_issuer_url = "https://eastus.oic.prod-aks.azure.com/12345678-1234-1234-1234-1234567890ab/abcdef1234567890/"
  mock_node_resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MC_test-workload-identities-rg_test-aks-cluster_eastus"
}

module "identities" {
  source = "../../"

  prefix      = "test"
  customer    = "example"
  stage       = "dev"
  region_abbv = "eus"

  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location
  
  cluster_name = "test-aks-cluster"
  create_aks_identity = true
  
  # Workload identity configuration
  enable_workload_identity = true
  aks_oidc_issuer_url      = local.mock_oidc_issuer_url
  node_resource_group_id   = local.mock_node_resource_group_id
  
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