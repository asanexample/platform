/**
 * # Terraform State Backup Module
 *
 * This module implements automated backup of Terraform state files from an Azure storage account.
 * It creates a secondary storage account in a different region for backup storage and sets up
 * an Azure Function to perform scheduled backups.
 */

# Create a storage account for backup in a different region for disaster recovery
resource "azurerm_storage_account" "backup" {
  name                     = var.backup_storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.backup_location
  account_tier             = "Standard"
  account_replication_type = "GRS"  # Geo-redundant storage for extra protection
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    versioning_enabled = true  # Keep versions of state files
    
    container_delete_retention_policy {
      days = 30  # Retain deleted containers for 30 days
    }

    delete_retention_policy {
      days = 30  # Retain deleted blobs for 30 days
    }
  }

  # Network rules to restrict access
  network_rules {
    default_action = "Deny"
    ip_rules       = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
    bypass         = ["AzureServices"]  # Allow Azure services to access
  }

  tags = merge(var.tags, {
    purpose = "terraform-state-backup"
  })
}

# Create a container for state file backups
resource "azurerm_storage_container" "backup" {
  name                  = "terraform-state-backups"
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
}

# Implement storage policy for blob retention
resource "azurerm_storage_management_policy" "backup_retention" {
  storage_account_id = azurerm_storage_account.backup.id

  rule {
    name    = "terraform-state-retention"
    enabled = true
    filters {
      prefix_match = ["terraform-state-backups/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30   # Move to cool tier after 30 days
        tier_to_archive_after_days_since_modification_greater_than = 90   # Move to archive tier after 90 days
        delete_after_days_since_modification_greater_than          = 1095 # Delete after 3 years
      }
      snapshot {
        change_tier_to_archive_after_days_since_creation = 90
        change_tier_to_cool_after_days_since_creation    = 30
        delete_after_days_since_creation_greater_than    = 365 # Delete snapshots after 1 year
      }
      version {
        change_tier_to_archive_after_days_since_creation = 90
        change_tier_to_cool_after_days_since_creation    = 30
        delete_after_days_since_creation_greater_than    = 365 # Delete older versions after 1 year
      }
    }
  }
}

# Create a user-assigned managed identity for the function app
resource "azurerm_user_assigned_identity" "backup_function" {
  name                = "id-tfstate-backup-${var.environment}-${var.region_abbv}"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  tags = merge(var.tags, {
    purpose = "terraform-state-backup-function"
  })
}

# Create app service plan for the function
resource "azurerm_service_plan" "backup_function" {
  name                = "plan-tfstate-backup-${var.environment}-${var.region_abbv}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan for cost optimization

  tags = merge(var.tags, {
    purpose = "terraform-state-backup-function"
  })
}

# Create storage account for function app
resource "azurerm_storage_account" "function" {
  name                     = "stfuncapp${var.environment}${var.region_abbv}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = merge(var.tags, {
    purpose = "terraform-state-backup-function"
  })
}

# Create function app
resource "azurerm_linux_function_app" "backup_function" {
  name                       = "func-tfstate-backup-${var.environment}-${var.region_abbv}"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.backup_function.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key

  # Use managed identity
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.backup_function.id]
  }

  site_config {
    application_stack {
      python_version = "3.10"
    }
    
    application_insights_connection_string = var.application_insights_connection_string
    application_insights_key               = var.application_insights_key
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
    "SOURCE_STORAGE_ACCOUNT"         = var.source_storage_account_name
    "SOURCE_CONTAINER_NAME"          = var.source_container_name
    "BACKUP_STORAGE_ACCOUNT"         = azurerm_storage_account.backup.name
    "BACKUP_CONTAINER_NAME"          = azurerm_storage_container.backup.name
    "BACKUP_FREQUENCY"               = var.backup_frequency
    "BACKUP_RETENTION_DAYS"          = var.backup_retention_days
    "DAILY_BACKUP_TIME"              = var.daily_backup_time
    "WEEKLY_BACKUP_DAY"              = var.weekly_backup_day
    "MONTHLY_BACKUP_DAY"             = var.monthly_backup_day
    "MANAGED_IDENTITY_CLIENT_ID"     = azurerm_user_assigned_identity.backup_function.client_id
    "LOG_ANALYTICS_WORKSPACE_ID"     = var.log_analytics_workspace_id
    "ALERT_EMAIL"                    = var.alert_email
  }

  tags = merge(var.tags, {
    purpose = "terraform-state-backup-function"
  })
}

# Upload the function code as a zip deployment
resource "azurerm_function_app_function" "backup_function" {
  name            = "TerraformStateBackup"
  function_app_id = azurerm_linux_function_app.backup_function.id
  
  config_json = jsonencode({
    "bindings": [
      {
        "name": "mytimer",
        "type": "timerTrigger",
        "direction": "in",
        "schedule": "0 0 ${var.daily_backup_time} * * *"
      }
    ]
  })
  
  language = "Python"
  
  file {
    name    = "__init__.py"
    content = file("${path.module}/function/backup_function.py")
  }
  
  file {
    name    = "requirements.txt"
    content = file("${path.module}/function/requirements.txt")
  }
}

# Grant the function access to source storage account
resource "azurerm_role_assignment" "source_storage_reader" {
  scope                = var.source_storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.backup_function.principal_id
}

# Grant the function access to backup storage account
resource "azurerm_role_assignment" "backup_storage_contributor" {
  scope                = azurerm_storage_account.backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.backup_function.principal_id
}

# Create monitor action group for alerts
resource "azurerm_monitor_action_group" "backup_alerts" {
  name                = "ag-tfstate-backup-${var.environment}-${var.region_abbv}"
  resource_group_name = var.resource_group_name
  short_name          = "tfbackup"

  email_receiver {
    name                    = "admin"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
  
  tags = merge(var.tags, {
    purpose = "terraform-state-backup-alerts"
  })
}

# Create alert for backup failures
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "backup_failure" {
  name                = "alert-tfstate-backup-failure-${var.environment}-${var.region_abbv}"
  resource_group_name = var.resource_group_name
  location            = var.location

  evaluation_frequency = "P1D"  # Daily evaluation
  window_duration      = "P1D"  # Evaluate over 1 day
  scopes               = [var.log_analytics_workspace_id]
  severity             = 1
  
  criteria {
    query                   = <<-QUERY
      FunctionLogs
      | where FunctionName == "TerraformStateBackup"
      | where Message contains "ERROR" or Message contains "FAILED"
      | summarize count() by bin(TimeGenerated, 1d)
    QUERY
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  auto_mitigation_enabled = true
  
  action {
    action_groups = [azurerm_monitor_action_group.backup_alerts.id]
  }
  
  tags = merge(var.tags, {
    purpose = "terraform-state-backup-alerts"
  })
}

# Create alert for missing backups
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "backup_missing" {
  name                = "alert-tfstate-backup-missing-${var.environment}-${var.region_abbv}"
  resource_group_name = var.resource_group_name
  location            = var.location

  evaluation_frequency = "P1D"  # Daily evaluation
  window_duration      = "P1D"  # Evaluate over 1 day
  scopes               = [var.log_analytics_workspace_id]
  severity             = 1
  
  criteria {
    query                   = <<-QUERY
      FunctionLogs
      | where FunctionName == "TerraformStateBackup"
      | where Message contains "Backup completed successfully"
      | summarize count() by bin(TimeGenerated, 1d)
      | where count_ == 0
    QUERY
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  auto_mitigation_enabled = true
  
  action {
    action_groups = [azurerm_monitor_action_group.backup_alerts.id]
  }
  
  tags = merge(var.tags, {
    purpose = "terraform-state-backup-alerts"
  })
} 