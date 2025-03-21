/**
 * # Key Vault Module - Advanced Test
 * 
 * This test verifies advanced functionality of the key vault module
 * including access policies, network rules, and private endpoints.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
  }
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Advanced test for key vault with access policies, network rules, and private endpoint
run "advanced_key_vault" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Custom key vault name
    name = "test-secure-vault"
    name_components = {
      prefix       = "tst"
      environment  = "prod"
      region_abbv  = "eus"
      instance     = "01"
    }
    
    # Premium SKU for HSM support
    sku_name = "premium"
    
    # Enhanced security settings
    enabled_for_disk_encryption = true
    purge_protection_enabled    = true
    soft_delete_retention_days  = 90
    
    # Use access policies instead of RBAC
    enable_rbac_authorization = false
    
    # Restrict public network access
    public_network_access_enabled = false
    
    # Configure network rules
    network_acls = {
      bypass                     = "AzureServices"
      default_action             = "Deny"
      ip_rules                   = ["203.0.113.0/24", "198.51.100.10"]
      virtual_network_subnet_ids = [
        "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-vnet-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/subnet1",
        "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-vnet-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/subnet2"
      ]
    }
    
    # Set up access policies for different entities - using map format
    access_policies = {
      admin_user = {
        object_id               = "00000000-0000-0000-0000-000000000001"
        certificate_permissions = ["Get", "List", "Create", "Delete"]
        key_permissions         = ["Get", "List", "Create", "Delete", "Encrypt", "Decrypt"]
        secret_permissions      = ["Get", "List", "Set", "Delete"]
        storage_permissions     = []
      },
      readonly_user = {
        object_id               = "00000000-0000-0000-0000-000000000002"
        certificate_permissions = ["Get", "List"]
        key_permissions         = ["Get", "List"]
        secret_permissions      = ["Get", "List"]
        storage_permissions     = []
      }
    }
    
    # Set up private endpoint for secure access
    private_endpoint = {
      create              = true
      name                = "test-kv-pe"
      subnet_id           = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-vnet-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/subnet1"
      private_dns_zone_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-vnet-rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    }
    
    # Comprehensive tags
    tags = {
      environment     = "production"
      criticality     = "high"
      data-class      = "confidential"
      service-owner   = "security-team"
      cost-center     = "12345"
      application     = "core-secrets"
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  # Validate key vault properties
  assert {
    condition     = output.name == "test-secure-vault"
    error_message = "Key vault name doesn't match expected value"
  }

  assert {
    condition     = !output.public_network_access_enabled
    error_message = "Public network access should be disabled"
  }
} 