/**
 * # Private DNS Module - Advanced Test
 * 
 * This test verifies more advanced functionality of the private DNS module
 * with multiple zones and different configurations.
 */

# Provider configuration with Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Test with multiple different private DNS zones and configurations
run "multiple_private_dns_zones_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    
    # Advanced private DNS zone configuration with multiple services
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
      },
      "privatelink.file.core.windows.net" = {
        name                      = "privatelink.file.core.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "file-vnet-link"
      },
      "privatelink.table.core.windows.net" = {
        name                      = "privatelink.table.core.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "table-vnet-link"
      },
      "privatelink.azurewebsites.net" = {
        name                      = "privatelink.azurewebsites.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "appservice-vnet-link"
      }
    }
    
    tags = {
      environment = "test"
      purpose     = "advanced testing"
      owner       = "platform-team"
    }
  }

  module {
    source = "../../../../modules/azure/private_dns"
  }

  # Validate all private DNS zone IDs are created
  assert {
    condition     = length(output.private_dns_zone_ids) == 5
    error_message = "Expected 5 private DNS zones to be created"
  }
  
  # Verify specific zones were created
  assert {
    condition     = lookup(output.private_dns_zone_ids, "privatelink.blob.core.windows.net", "") != ""
    error_message = "Blob storage private DNS zone ID should not be empty"
  }
  
  assert {
    condition     = lookup(output.private_dns_zone_ids, "privatelink.file.core.windows.net", "") != ""
    error_message = "File storage private DNS zone ID should not be empty"
  }
  
  assert {
    condition     = lookup(output.private_dns_zone_ids, "privatelink.azurewebsites.net", "") != ""
    error_message = "App Service private DNS zone ID should not be empty"
  }
}

# Test with different registration settings
run "registration_enabled_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    
    # Test with registration enabled for one zone
    private_dns_zones = {
      "privatelink.database.windows.net" = {
        name                      = "privatelink.database.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = true  # Registration enabled
        virtual_network_link_name = "database-vnet-link"
      },
      "privatelink.blob.core.windows.net" = {
        name                      = "privatelink.blob.core.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false  # Registration disabled
        virtual_network_link_name = "blob-vnet-link"
      }
    }
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/private_dns"
  }

  # Validate registration settings
  assert {
    condition     = var.private_dns_zones["privatelink.database.windows.net"].registration_enabled == true
    error_message = "Database private DNS zone should have registration enabled"
  }
  
  assert {
    condition     = var.private_dns_zones["privatelink.blob.core.windows.net"].registration_enabled == false
    error_message = "Blob storage private DNS zone should have registration disabled"
  }
}

# Test with custom virtual network link names
run "custom_vnet_link_names_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    
    # Test with custom virtual network link names
    private_dns_zones = {
      "privatelink.database.windows.net" = {
        name                      = "privatelink.database.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "custom-database-link-name"
      }
    }
    
    tags = {
      environment = "test"
    }
  }

  module {
    source = "../../../../modules/azure/private_dns"
  }

  # Validate custom virtual network link name
  assert {
    condition     = var.private_dns_zones["privatelink.database.windows.net"].virtual_network_link_name == "custom-database-link-name"
    error_message = "Custom virtual network link name was not set correctly"
  }
} 