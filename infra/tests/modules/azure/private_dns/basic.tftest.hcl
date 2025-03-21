/**
 * # Private DNS Module - Basic Test
 * 
 * This test verifies the basic functionality of the private DNS module
 * with minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Basic test for private DNS zone creation with minimal configuration
run "basic_private_dns_zones" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    
    # Basic private DNS zone configuration
    private_dns_zones = {
      "privatelink.database.windows.net" = {
        name                      = "privatelink.database.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "database-vnet-link"
      },
      "privatelink.blob.core.windows.net" = {
        name                      = "privatelink.blob.core.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "blob-vnet-link"
      }
    }
    
    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/private_dns"
  }

  # Validate private DNS zone IDs
  assert {
    condition     = length(output.private_dns_zone_ids) == 2
    error_message = "Expected 2 private DNS zones to be created"
  }
  
  assert {
    condition     = lookup(output.private_dns_zone_ids, "privatelink.database.windows.net", "") != ""
    error_message = "Database private DNS zone ID should not be empty"
  }
  
  assert {
    condition     = lookup(output.private_dns_zone_ids, "privatelink.blob.core.windows.net", "") != ""
    error_message = "Blob storage private DNS zone ID should not be empty"
  }
} 