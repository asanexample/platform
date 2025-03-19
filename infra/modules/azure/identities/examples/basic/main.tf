/**
 * # Basic Example for Azure Identities Module
 *
 * This example shows how to create a basic AKS cluster identity.
 */

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

resource "azurerm_resource_group" "test" {
  name     = "test-identities-rg"
  location = "eastus"
}

module "identities" {
  source = "../../"

  prefix      = "test"
  customer    = "example"
  stage       = "dev"
  region_abbv = "eus"

  resource_group_name = azurerm_resource_group.test.name
  location           = azurerm_resource_group.test.location
  
  cluster_name = "test-aks-cluster"
  create_aks_identity = true
  
  tags = {
    Environment = "Test"
    Terraform   = "True"
  }
} 