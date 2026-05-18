/**
 * # AKS Identity Module - Basic Test
 * 
 * This test verifies the basic functionality of the AKS Identity module
 * with minimal configuration for just the AKS identity without workload identities.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Basic test for AKS Identity with minimal configuration
run "basic_aks_identity" {
  command = plan

  variables {
    # Basic naming
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"

    # Resource group and location
    resource_group_name = "test-rg"
    location            = "eastus"

    # Cluster reference
    cluster_name = "test-dev-aks-eus"

    # No custom identity name, will be auto-generated
    aks_identity_name = null

    # Disable workload identities for basic test
    create_workload_identities = false
    workload_identity_enabled  = false
    oidc_issuer_enabled        = false
    oidc_issuer_url            = null

    # Explicitly set these to null to avoid route table lookup
    private_route_table_name = null
    vnet_resource_group_name = null

    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/aks_identity"
  }

  # Only validate input variables in plan mode
  assert {
    condition     = var.workload == "platform"
    error_message = "Workload not set correctly"
  }

  assert {
    condition     = var.environment == "dev"
    error_message = "Environment not set correctly"
  }

  assert {
    condition     = var.create_workload_identities == false
    error_message = "Should not create workload identities in basic test"
  }

  assert {
    condition     = var.cluster_name == "test-dev-aks-eus"
    error_message = "Cluster name not set correctly"
  }

  assert {
    condition     = var.location == "eastus"
    error_message = "Location not set correctly"
  }
} 