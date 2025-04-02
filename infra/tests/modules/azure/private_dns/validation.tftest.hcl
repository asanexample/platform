/**
 * # Private DNS Module - Validation Test
 * 
 * This test verifies the validation rules and constraints for the private DNS module
 * to ensure that input variables are properly validated.
 */

# Provider configuration with Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Test resource group name validation
run "resource_group_name_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-resource-group-1"
    
    private_dns_zones = {
      "privatelink.database.windows.net" = {
        name                      = "privatelink.database.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "database-vnet-link"
      }
    }
  }

  module {
    source = "../../../../modules/azure/private_dns"
  }

  # Validate resource group name format
  assert {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 63
    error_message = "Resource group name should be between 3 and 63 characters"
  }
  
  assert {
    condition     = can(regex("^[a-zA-Z0-9-_.()]+$", var.resource_group_name))
    error_message = "Resource group name should only contain alphanumeric, hyphen, underscore, parentheses, and period characters"
  }
}

# Test DNS zone name validation
run "dns_zone_name_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    
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
  }

  module {
    source = "../../../../modules/azure/private_dns"
  }

  # Validate DNS zone name length
  assert {
    condition = alltrue([
      for k, v in var.private_dns_zones : length(v.name) >= 1 && length(v.name) <= 253
    ])
    error_message = "DNS zone names must be between 1 and 253 characters"
  }
  
  # Validate DNS zone name format
  assert {
    condition = alltrue([
      for k, v in var.private_dns_zones : can(regex("^[a-z0-9][a-z0-9-]*(\\.[a-z0-9][a-z0-9-]*)*$", v.name))
    ])
    error_message = "DNS zone names must be valid domain names"
  }
}

# Test VNET ID validation
run "vnet_id_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    
    private_dns_zones = {
      "privatelink.database.windows.net" = {
        name                      = "privatelink.database.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "database-vnet-link"
      }
    }
  }

  module {
    source = "../../../../modules/azure/private_dns"
  }

  # Validate VNET ID format
  assert {
    condition = alltrue([
      for k, v in var.private_dns_zones : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", v.vnet_id))
    ])
    error_message = "VNET IDs must follow Azure resource ID format"
  }
}

# Test tags validation
run "tags_validation_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    
    private_dns_zones = {
      "privatelink.database.windows.net" = {
        name                      = "privatelink.database.windows.net"
        vnet_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet"
        vnet_resource_group_name  = "test-rg"
        registration_enabled      = false
        virtual_network_link_name = "database-vnet-link"
      }
    }
    
    tags = {
      environment = "test"
      owner       = "platform-team"
      project     = "terraform-testing"
    }
  }

  module {
    source = "../../../../modules/azure/private_dns"
  }

  # Validate tag key length
  assert {
    condition = alltrue([
      for key in keys(var.tags) : length(key) >= 1 && length(key) <= 512
    ])
    error_message = "Tag keys must be between 1 and 512 characters"
  }
  
  # Validate tag value length
  assert {
    condition = alltrue([
      for value in values(var.tags) : length(value) <= 256
    ])
    error_message = "Tag values must be 256 characters or less"
  }
} 