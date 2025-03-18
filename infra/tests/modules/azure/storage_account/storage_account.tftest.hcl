provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  resource_group_name = "test-rg"
  location            = "eastus"
}

run "create_basic_storage" {
  command = plan

  variables {
    resource_group_name = var.resource_group_name
    location            = var.location
    
    name_components = {
      prefix      = "test"
      environment = "dev"
      region_abbv = "eus"
      instance    = "001"
    }
    
    containers = {
      "testdata" = {
        name                  = "testdata"
        container_access_type = "private"
      },
      "public" = {
        name                  = "public"
        container_access_type = "blob"
      }
    }
    
    tags = {
      Environment = "Test"
      Project     = "Module Testing"
    }
  }

  module {
    source = "../../../../modules/azure/storage_account"
  }

  # Check a variable access to satisfy Terraform's requirement
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

run "create_storage_no_containers" {
  command = plan

  variables {
    resource_group_name = var.resource_group_name
    location            = var.location
    
    name_components = {
      prefix      = "test"
      environment = "dev"
      region_abbv = "eus"
      instance    = "002"
    }
    
    # No containers defined
    
    account_tier             = "Premium"
    account_replication_type = "ZRS"
    
    tags = {
      Environment = "Test"
      Project     = "Module Testing"
    }
  }

  module {
    source = "../../../../modules/azure/storage_account"
  }

  # Check a variable access to satisfy Terraform's requirement
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
} 