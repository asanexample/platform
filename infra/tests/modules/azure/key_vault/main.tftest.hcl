provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  location = "eastus"
}

# ---------------------------------------------------------------------------------------------------------------------
# BASIC KEY VAULT TEST
# This test verifies that the key vault module creates a basic key vault with default settings
# ---------------------------------------------------------------------------------------------------------------------
run "test_basic_key_vault" {
  command = plan

  variables {
    resource_group_name = "test-kv-rg"
    location            = var.location
    name                = "test-basic-kv"
    
    tags = {
      Environment = "Test"
      Project     = "Key Vault Tests"
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  # Check that a key vault is created with the expected name
  assert {
    condition     = output.name == "test-basic-kv"
    error_message = "Key vault name doesn't match expected value"
  }
  
  # Verify that RBAC is enabled by default
  assert {
    condition     = length(output.access_policy_ids) == 0
    error_message = "Access policies should not be created when RBAC is enabled"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY VAULT WITH ACCESS POLICIES TEST
# This test verifies that the key vault module creates access policies correctly when RBAC is disabled
# ---------------------------------------------------------------------------------------------------------------------
run "test_key_vault_with_access_policies" {
  command = plan

  variables {
    resource_group_name = "test-kv-policy-rg"
    location            = var.location
    name                = "test-policy-kv"
    
    # Disable RBAC so we can use access policies
    enable_rbac_authorization = false
    
    # Add access policies
    access_policies = {
      "admin" = {
        object_id = "00000000-0000-0000-0000-000000000000" # This is a placeholder ID
        secret_permissions = [
          "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
        ]
        key_permissions = [
          "Get", "List", "Create", "Delete", "Update"
        ]
      },
      "reader" = {
        object_id = "11111111-1111-1111-1111-111111111111" # This is a placeholder ID
        secret_permissions = [
          "Get", "List"
        ]
      }
    }
    
    tags = {
      Environment = "Test"
      Project     = "Key Vault Tests"
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  # Check that a key vault is created with the expected name
  assert {
    condition     = output.name == "test-policy-kv"
    error_message = "Key vault name doesn't match expected value"
  }
  
  # Verify that access policies are created (not empty when RBAC is disabled)
  assert {
    condition     = length(output.access_policy_ids) == 2
    error_message = "Expected 2 access policies but got ${length(output.access_policy_ids)}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY VAULT WITH NETWORK ACLS TEST
# This test verifies that the key vault module handles network ACLs correctly
# ---------------------------------------------------------------------------------------------------------------------
run "test_key_vault_with_network_acls" {
  command = plan

  variables {
    resource_group_name = "test-kv-network-rg"
    location            = var.location
    name                = "test-network-kv"
    
    # Configure network ACLs
    network_acls = {
      bypass                     = "AzureServices"
      default_action             = "Deny"
      ip_rules                   = ["203.0.113.0/24"]
      virtual_network_subnet_ids = ["subnet-id-1", "subnet-id-2"]
    }
    
    tags = {
      Environment = "Test"
      Project     = "Key Vault Tests"
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  # Check that a key vault is created with the expected name
  assert {
    condition     = output.name == "test-network-kv"
    error_message = "Key vault name doesn't match expected value"
  }
  
  # Verify public network access (we can't directly test network_acls in outputs)
  assert {
    condition     = output.public_network_access_enabled == true
    error_message = "Public network access should be enabled when private endpoint is not created"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY VAULT WITH AUTO-GENERATED NAME TEST
# This test verifies that the key vault module correctly generates a name based on name components
# ---------------------------------------------------------------------------------------------------------------------
run "test_key_vault_with_auto_name" {
  command = plan

  variables {
    resource_group_name = "test-kv-autoname-rg"
    location            = var.location
    
    # Empty name to trigger auto-generation
    name = ""
    
    # Provide name components
    name_components = {
      prefix      = "vip"
      environment = "dev"
      region_abbv = "eus"
      instance    = "001"
    }
    
    tags = {
      Environment = "Test"
      Project     = "Key Vault Tests"
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  # Check that the key vault name is generated correctly
  assert {
    condition     = output.name == "vipdeveuskv001"
    error_message = "Auto-generated key vault name doesn't match expected pattern"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY VAULT WITH PRIVATE ENDPOINT TEST
# This test verifies that the key vault module correctly creates a private endpoint
# ---------------------------------------------------------------------------------------------------------------------
run "test_key_vault_with_private_endpoint" {
  command = plan

  variables {
    resource_group_name = "test-kv-pe-rg"
    location            = var.location
    name                = "test-pe-kv"
    
    # Configure private endpoint
    private_endpoint = {
      create               = true
      subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/test-subnet"
      private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
    }
    
    tags = {
      Environment = "Test"
      Project     = "Key Vault Tests"
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  # Check that a key vault is created with the expected name
  assert {
    condition     = output.name == "test-pe-kv"
    error_message = "Key vault name doesn't match expected value"
  }
  
  # Verify that public network access is disabled when private endpoint is created
  assert {
    condition     = output.public_network_access_enabled == false
    error_message = "Public network access should be disabled when private endpoint is created"
  }
  
  # Verify that private endpoint is created
  assert {
    condition     = length(output.private_endpoint_ids) == 1
    error_message = "Expected 1 private endpoint but got ${length(output.private_endpoint_ids)}"
  }
} 