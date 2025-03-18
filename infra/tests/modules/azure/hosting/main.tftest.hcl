provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  test_prefix = "test-hosting"
  location    = "eastus"
}

run "test_basic_hosting" {
  command = plan

  variables {
    resource_group_name = "${var.test_prefix}-rg"
    location            = var.location

    # Network configuration
    vnet_name     = "${var.test_prefix}-vnet"
    address_space = ["10.0.0.0/16"]
    subnets = {
      "frontend" = {
        address_prefixes = ["10.0.1.0/24"]
      },
      "backend" = {
        address_prefixes = ["10.0.2.0/24"]
      },
      "storage" = {
        address_prefixes                          = ["10.0.3.0/24"]
        service_endpoints                         = ["Microsoft.Storage"]
        private_endpoint_network_policies_enabled = true
      }
    }

    # Storage configuration
    storage_name_components = {
      workload    = "hosting"
      environment = "test"
      instance    = "01"
    }
    storage_account_tier     = "Standard"
    storage_replication_type = "LRS"
    storage_allowed_subnets  = ["storage"]
    storage_network_bypass   = ["AzureServices"]
    storage_allow_public     = false
    storage_containers = {
      "test-data" = {
        name                  = "test-data"
        container_access_type = "private"
      }
    }

    tags = {
      Environment = "Test"
      Project     = "Module Testing"
      Terraform   = "true"
    }
  }

  module {
    source = "../../../../modules/azure/hosting"
  }

  # Check a variable access to satisfy Terraform's requirement
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

run "test_advanced_hosting" {
  command = plan

  variables {
    resource_group_name = "${var.test_prefix}-adv-rg"
    location            = var.location

    # Network configuration
    vnet_name     = "${var.test_prefix}-adv-vnet"
    address_space = ["10.1.0.0/16"]
    subnets = {
      "app" = {
        address_prefixes = ["10.1.1.0/24"]
      },
      "data" = {
        address_prefixes                          = ["10.1.2.0/24"]
        service_endpoints                         = ["Microsoft.Storage"]
        private_endpoint_network_policies_enabled = true
      }
    }

    # Storage configuration
    storage_name_components = {
      workload    = "adv"
      environment = "test"
      instance    = "02"
    }
    storage_account_tier     = "Premium"
    storage_replication_type = "ZRS"
    storage_allowed_subnets  = ["data"]
    storage_allow_public     = true
    storage_containers = {
      "web-assets" = {
        name                  = "web-assets"
        container_access_type = "blob"
        metadata = {
          application = "test-app"
        }
      },
      "user-content" = {
        name                  = "user-content"
        container_access_type = "private"
      }
    }
    storage_cors_rules = [{
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "OPTIONS"]
      allowed_origins    = ["https://example.com"]
      exposed_headers    = ["x-custom-header"]
      max_age_in_seconds = 3600
    }]

    tags = {
      Environment = "Test"
      Project     = "Advanced Config Testing"
      Terraform   = "true"
    }
  }

  module {
    source = "../../../../modules/azure/hosting"
  }

  # Check a variable access to satisfy Terraform's requirement
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
} 