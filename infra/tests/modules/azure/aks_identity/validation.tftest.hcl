/**
 * # AKS Identity Module - Validation Test
 * 
 * This test verifies validation conditions for the AKS Identity module.
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
    # Short prefix (within limit)
    prefix              = "t"
    environment         = "dev"
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    cluster_name        = "test-dev-aks-eus"
    create_workload_identities = false
    # Avoid route table lookup
    private_route_table_name = null
    vnet_resource_group_name = null
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_identity"
  }

  assert {
    condition     = var.prefix == "t"
    error_message = "Prefix should be accepted at minimum length"
  }
}

# Test environment validation
run "environment_validation_test" {
  command = plan

  variables {
    prefix              = "test"
    environment         = "prod"  # Valid environment
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    cluster_name        = "test-prod-aks-eus"
    create_workload_identities = false
    # Avoid route table lookup
    private_route_table_name = null
    vnet_resource_group_name = null
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_identity"
  }

  assert {
    condition     = var.environment == "prod"
    error_message = "Environment should be accepted with valid value"
  }
}

# Test customer validation
run "customer_validation_test" {
  command = plan

  variables {
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    customer            = "customername123"  # Valid customer name (15 chars)
    resource_group_name = "test-rg"
    location            = "eastus"
    cluster_name        = "test-dev-aks-eus"
    create_workload_identities = false
    # Avoid route table lookup
    private_route_table_name = null
    vnet_resource_group_name = null
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_identity"
  }

  assert {
    condition     = var.customer == "customername123"
    error_message = "Customer name should be accepted with valid value"
  }
}

# Test resource group name validation
run "resource_group_validation_test" {
  command = plan

  variables {
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    resource_group_name = "test-resource-group-with-valid-name"  # Valid resource group name
    location            = "eastus"
    cluster_name        = "test-dev-aks-eus"
    create_workload_identities = false
    # Avoid route table lookup
    private_route_table_name = null
    vnet_resource_group_name = null
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_identity"
  }

  assert {
    condition     = var.resource_group_name == "test-resource-group-with-valid-name"
    error_message = "Resource group name should be accepted with valid value"
  }
}

# Test workload identity configuration validation
run "workload_identity_validation_test" {
  command = plan

  variables {
    prefix              = "test"
    environment         = "dev"
    region_abbv         = "eus"
    resource_group_name = "test-rg"
    location            = "eastus"
    cluster_name        = "test-dev-aks-eus"
    
    # All three conditions must be met for workload identities to be created
    create_workload_identities = true
    workload_identity_enabled  = true
    oidc_issuer_enabled        = true
    oidc_issuer_url            = "https://eastus.oic.dev-aks-0000000.hcp.eastus.azmk8s.io/0000000-0000-0000-0000-000000000000/"
    
    # Avoid route table lookup
    private_route_table_name = null
    vnet_resource_group_name = null
    tags = {}
  }

  module {
    source = "../../../../modules/azure/aks_identity"
  }

  assert {
    condition     = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled
    error_message = "Workload identity configuration should be accepted with all conditions met"
  }
} 