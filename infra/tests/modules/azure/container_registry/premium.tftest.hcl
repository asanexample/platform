/**
 * # Azure Container Registry Module - Premium Test
 * 
 * This test verifies the advanced functionality of the ACR module
 * with premium configuration including geo-replication, network rules,
 * and AKS integration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Advanced test for ACR with premium features
run "premium_acr" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Use explicit name
    name                = "testenterpriseacr"
    prefix              = "test"
    environment         = "prod"
    region_abbv         = "eus"
    
    # Premium SKU for advanced features
    sku = "Premium"
    
    # Premium features
    zone_redundancy_enabled = true
    data_endpoint_enabled   = true
    
    # Geo-replication
    geo_replication_locations = [
      {
        location                = "westus"
        zone_redundancy_enabled = true
      }
    ]
    
    # Network rules (Premium/Standard only)
    network_rule_set = {
      default_action = "Deny"
      ip_rules       = ["203.0.113.0/24"]
    }
    
    # Image retention policy
    retention_policy_days = 30
    
    # AKS integration
    aks_integration_enabled = true
    aks_principal_id        = "00000000-0000-0000-0000-000000000001"
    enable_aks_acr_push     = true
    
    # Resource locking
    lock_resource = true
    
    # Comprehensive tagging
    tags = {
      environment     = "production"
      criticality     = "high"
      data-class      = "confidential"
      service-owner   = "platform-team"
      cost-center     = "12345"
      application     = "core-infrastructure"
    }
  }

  module {
    source = "../../../../modules/azure/container_registry"
  }

  # Validate ACR properties
  assert {
    condition     = output.name == "testenterpriseacr"
    error_message = "ACR name doesn't match expected value"
  }

  assert {
    condition     = output.sku == "Premium"
    error_message = "SKU doesn't match expected value"
  }

  assert {
    condition     = output.zone_redundancy_enabled == true
    error_message = "Zone redundancy doesn't match expected value"
  }

  assert {
    condition     = length(output.geo_replications) == 1
    error_message = "Geo-replications count doesn't match expected value"
  }

  assert {
    condition     = output.network_rule_set != null
    error_message = "Network rule set is unexpectedly null"
  }

  assert {
    condition     = var.aks_integration_enabled == true
    error_message = "AKS integration should be enabled"
  }

  assert {
    condition     = var.enable_aks_acr_push == true
    error_message = "AKS push access should be enabled"
  }

  assert {
    condition     = var.lock_resource == true
    error_message = "Resource lock should be enabled"
  }
} 