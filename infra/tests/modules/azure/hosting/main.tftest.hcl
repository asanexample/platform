provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  test_prefix = "test-hosting"
  location    = "eastus"
}

# ---------------------------------------------------------------------------------------------------------------------
# SHARED RESOURCES HOSTING TEST
# This test verifies the hosting module works with the naming module for shared resources
# ---------------------------------------------------------------------------------------------------------------------
run "test_shared_resources_hosting" {
  command = plan

  variables {
    # Naming module parameters
    prefix        = "vip"
    stage         = "dev"
    region_abbv   = "eus"
    
    # No customer provided (for shared resources)
    
    # Required parameters
    location      = var.location
    
    # Network configuration
    address_space = ["10.1.0.0/16"]
    subnets = {
      "node" = {
        address_prefixes = ["10.1.1.0/24"]
      },
      "app" = {
        address_prefixes = ["10.1.2.0/24"]
      },
      "endpoint" = {
        address_prefixes  = ["10.1.3.0/24"]
        service_endpoints = ["Microsoft.Storage"]
      }
    }

    # Storage configuration
    storage_account_tier     = "Standard"
    storage_replication_type = "LRS"
    storage_allowed_subnets  = ["endpoint"]
    storage_allow_public     = false
    storage_containers = {
      "assets" = {
        name                  = "assets"
        container_access_type = "private"
      }
    }

    tags = {
      Environment = "Dev"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/hosting"
  }

  # Check that the naming module outputs are used
  assert {
    condition     = output.resource_group_name == "vip-dev-rg-eus"
    error_message = "Resource group name should use naming module pattern"
  }

  assert {
    condition     = output.vnet_name == "vip-dev-vnet-eus"
    error_message = "VNet name should use naming module pattern"
  }

  assert {
    condition     = output.storage_account_name == "vipdevsaeus"
    error_message = "Storage account name should use naming module pattern"
  }

  # Verify naming module output is available
  assert {
    condition     = output.naming != null
    error_message = "Naming module output should be available"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CUSTOMER-SPECIFIC RESOURCES HOSTING TEST
# This test verifies the hosting module works with the naming module for customer-specific resources
# ---------------------------------------------------------------------------------------------------------------------
run "test_customer_specific_hosting" {
  command = plan

  variables {
    # Naming module parameters
    prefix        = "vip"
    customer      = "contoso"
    stage         = "test"
    region_abbv   = "wus"
    
    # Required parameters
    location      = "westus"
    
    # Network configuration
    address_space = ["10.2.0.0/16"]
    subnets = {
      "frontend" = {
        address_prefixes = ["10.2.1.0/24"]
      },
      "backend" = {
        address_prefixes = ["10.2.2.0/24"]
      },
      "database" = {
        address_prefixes  = ["10.2.3.0/24"]
        service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
      }
    }

    # Storage configuration
    storage_account_tier     = "Premium"
    storage_replication_type = "ZRS"
    storage_allowed_subnets  = ["database"]
    storage_allow_public     = true
    storage_containers = {
      "public" = {
        name                  = "public"
        container_access_type = "blob"
      },
      "private" = {
        name                  = "private"
        container_access_type = "private"
      }
    }

    tags = {
      Environment = "Test"
      Customer    = "Contoso Corp"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/hosting"
  }

  # Check that the naming module outputs are used with customer name
  assert {
    condition     = output.resource_group_name == "vip-contoso-test-rg-wus"
    error_message = "Resource group name should include customer name"
  }

  assert {
    condition     = output.storage_account_name == "vipcontosotestsawus"
    error_message = "Storage account name should include normalized customer name"
  }

  # Verify subnet naming
  assert {
    condition     = contains(keys(output.subnet_ids), "frontend")
    error_message = "Subnet ID for frontend should be available"
  }
} 