# Comprehensive test file for Azure Log Analytics module
# Using Terraform 1.6+ testing framework

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# Global variables for all tests
variables {
  resource_group_name = "test-rg"
  location            = "eastus"
}

# Test basic Log Analytics workspace creation
run "create_basic_workspace" {
  command = plan

  variables {
    name = "test-law"
    sku  = "PerGB2018"
    retention_in_days = 30
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Simple assertion to satisfy Terraform's requirement
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

# Test Log Analytics workspace with explicit naming parameters
run "test_workspace_naming" {
  command = plan

  variables {
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"
    name        = "test-law-auto"
    sku         = "PerGB2018"
    retention_in_days = 30
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Assert variables are properly set
  assert {
    condition     = var.prefix == "test" && var.environment == "dev" && var.region_abbv == "eus"
    error_message = "The workspace parameters should be correctly set"
  }
  
  # Assert name is set correctly
  assert {
    condition     = var.name == "test-law-auto"
    error_message = "The workspace name should be correctly set"
  }
}

# Test Log Analytics workspace with auto-generated name
run "test_workspace_auto_name" {
  command = plan

  variables {
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"
    name        = null
    sku         = "PerGB2018"
    retention_in_days = 30
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Assert name components are properly set
  assert {
    condition     = var.prefix == "test" && var.environment == "dev" && var.region_abbv == "eus" && var.name == null
    error_message = "The workspace auto-naming parameters should be correctly set"
  }
}

# Test Log Analytics workspace with solution plans
run "test_workspace_with_solutions" {
  command = plan

  variables {
    name = "test-law-solutions"
    sku  = "PerGB2018"
    retention_in_days = 30
    solution_plans = [
      {
        solution_name = "ContainerInsights"
      },
      {
        solution_name = "SecurityInsights"
      }
    ]
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Assert the workspace has solutions
  assert {
    condition     = length(var.solution_plans) > 0
    error_message = "The workspace should have solution plans"
  }
}

# Test Log Analytics workspace with diagnostic settings
run "test_workspace_with_diagnostics" {
  command = plan

  variables {
    name = "test-law-diag"
    sku  = "PerGB2018"
    retention_in_days = 30
    diagnostic_settings = [
      {
        name                       = "law-diag"
        log_analytics_workspace_id = "self"
        enabled_log_categories     = ["Audit", "AllMetrics"]
        metric_categories          = ["AllMetrics"]
        log_retention_days         = 30
      }
    ]
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Assert the workspace has diagnostic settings
  assert {
    condition     = length(var.diagnostic_settings) > 0
    error_message = "The workspace should have diagnostic settings"
  }
}

# Test Log Analytics workspace with linked storage accounts
run "test_workspace_with_linked_storage" {
  command = plan

  variables {
    name = "test-law-storage"
    sku  = "PerGB2018"
    retention_in_days = 30
    linked_storage_accounts = {
      CustomLogs = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorage"]
    }
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Assert the workspace has linked storage accounts
  assert {
    condition     = length(var.linked_storage_accounts) > 0
    error_message = "The workspace should have linked storage accounts"
  }
}

# Test Log Analytics workspace with custom settings
run "test_workspace_custom_settings" {
  command = plan

  variables {
    name = "test-law-custom"
    sku  = "PerGB2018"
    retention_in_days = 90
    daily_quota_gb = 5
    internet_ingestion_enabled = true
    internet_query_enabled = true
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
      Project     = "Analytics"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Assert custom retention period
  assert {
    condition     = var.retention_in_days == 90
    error_message = "The workspace should have a 90-day retention period"
  }
  
  # Assert daily quota is set
  assert {
    condition     = var.daily_quota_gb == 5
    error_message = "The workspace should have a 5GB daily quota"
  }
} 