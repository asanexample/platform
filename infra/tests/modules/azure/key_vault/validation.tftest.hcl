/**
 * # Key Vault Module - Validation Test
 * 
 * This test verifies that the key vault module correctly validates input variables
 * and handles edge cases appropriately.
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
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test with maximum SKU and maximum soft delete retention
run "max_retention_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = "test-max-retention-vault"

    # Maximum SKU and retention configuration
    sku_name                   = "premium"
    soft_delete_retention_days = 90 # Maximum allowed
    purge_protection_enabled   = true

    # Basic required settings
    enable_rbac_authorization = true

    name_components = {
      prefix      = "tst"
      environment = "dev"
      region_abbv = "eus"
      instance    = "01"
    }

    # No network ACLs or access policies
    network_acls    = null
    access_policies = {} # Empty map instead of empty list
    private_endpoint = {
      create              = false
      name                = ""
      subnet_id           = ""
      private_dns_zone_id = ""
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  assert {
    condition     = output.name == "test-max-retention-vault"
    error_message = "Key vault name should match input value"
  }
}

# Test with minimum soft delete retention
run "min_retention_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = "test-min-retention-vault"

    # Minimum retention configuration
    sku_name                   = "standard"
    soft_delete_retention_days = 7 # Minimum allowed
    purge_protection_enabled   = false

    # Basic required settings
    enable_rbac_authorization = true

    name_components = {
      prefix      = "tst"
      environment = "dev"
      region_abbv = "eus"
      instance    = "01"
    }

    # No network ACLs or access policies
    network_acls    = null
    access_policies = {} # Empty map instead of empty list
    private_endpoint = {
      create              = false
      name                = ""
      subnet_id           = ""
      private_dns_zone_id = ""
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  assert {
    condition     = output.name == "test-min-retention-vault"
    error_message = "Key vault name should match input value"
  }
}

# Test with long key vault name (exactly at the limit)
run "max_name_length_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    # Key vault name max length is 24 characters
    name = "testmaxlengthkeyvaultnam"

    # Basic configuration
    sku_name                   = "standard"
    soft_delete_retention_days = 7
    purge_protection_enabled   = false
    enable_rbac_authorization  = true

    name_components = {
      prefix      = "tst"
      environment = "dev"
      region_abbv = "eus"
      instance    = "01"
    }

    # No network ACLs or access policies
    network_acls    = null
    access_policies = {} # Empty map instead of empty list
    private_endpoint = {
      create              = false
      name                = ""
      subnet_id           = ""
      private_dns_zone_id = ""
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  assert {
    condition     = output.name == "testmaxlengthkeyvaultnam"
    error_message = "Key vault with maximum length name should be accepted"
  }

  assert {
    condition     = length(output.name) == 24
    error_message = "Key vault name should be exactly 24 characters"
  }
}

# Test with simultaneous RBAC and access policies (RBAC overrides access policies)
run "rbac_and_policies_test" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = "test-rbac-policies-vault"

    # Enable RBAC but also provide access policies
    enable_rbac_authorization = true

    # These access policies should be ignored when RBAC is enabled
    access_policies = {
      test_user = {
        object_id               = "00000000-0000-0000-0000-000000000001"
        certificate_permissions = ["Get", "List"]
        key_permissions         = ["Get", "List"]
        secret_permissions      = ["Get", "List"]
        storage_permissions     = []
      }
    }

    # Basic configuration
    sku_name                   = "standard"
    soft_delete_retention_days = 7
    purge_protection_enabled   = false

    name_components = {
      prefix      = "tst"
      environment = "dev"
      region_abbv = "eus"
      instance    = "01"
    }

    # No network ACLs
    network_acls = null
    private_endpoint = {
      create              = false
      name                = ""
      subnet_id           = ""
      private_dns_zone_id = ""
    }
  }

  module {
    source = "../../../../modules/azure/key_vault"
  }

  assert {
    condition     = output.name == "test-rbac-policies-vault"
    error_message = "Key vault name should match input value"
  }
} 