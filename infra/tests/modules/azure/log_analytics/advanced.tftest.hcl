/**
 * # Log Analytics Module - Advanced Test
 * 
 * This test verifies advanced functionality of the Log Analytics module
 * including solution plans, diagnostic settings, and linked storage accounts.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Advanced test for Log Analytics workspace with solutions and diagnostic settings
run "advanced_log_analytics_workspace" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Use explicit name
    name                = "test-enterprise-law"
    prefix              = "test"
    environment         = "prod"
    region_abbv         = "eus"
    
    # Advanced log analytics configuration
    sku               = "PerGB2018"
    retention_in_days = 90
    daily_quota_gb    = 5
    
    # Custom network settings
    internet_ingestion_enabled = true
    internet_query_enabled     = true
    
    # Solution plans for common Azure services
    solution_plans = [
      {
        solution_name = "ContainerInsights"
      },
      {
        solution_name = "SecurityInsights"
      }
    ]
    
    # Diagnostic settings (using mock IDs for testing)
    diagnostic_settings = [
      {
        name                       = "law-diagnostics"
        log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/secondary-law"
        storage_account_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
        enabled_log_categories     = ["Audit", "AllMetrics"]
        metric_categories          = ["AllMetrics"]
        log_retention_days         = 30
      }
    ]
    
    # Linked storage accounts
    linked_storage_accounts = {
      CustomLogs = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/customlogs"]
      Query = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/querystore"]
    }
    
    # Comprehensive tagging
    tags = {
      environment     = "production"
      criticality     = "high"
      data-class      = "confidential"
      service-owner   = "platform-team"
      cost-center     = "12345"
      application     = "core-infrastructure"
    }
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # Validate Log Analytics workspace properties
  assert {
    condition     = output.name == "test-enterprise-law"
    error_message = "Log Analytics workspace name doesn't match expected value"
  }
  
  assert {
    condition     = length(output.solution_ids) == 2
    error_message = "Expected 2 solutions to be deployed"
  }
  
  assert {
    condition     = length(output.diagnostic_settings) == 1
    error_message = "Expected 1 diagnostic setting to be created"
  }
  
  assert {
    condition     = length(output.linked_storage_accounts) == 2
    error_message = "Expected 2 linked storage accounts to be created"
  }
} 