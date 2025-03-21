/**
 * # Azure Log Analytics Module
 * 
 * This module creates an Azure Log Analytics workspace with customizable settings for diagnostics and monitoring.
 * It supports solution packs, diagnostic settings, and can be integrated with multiple Azure services.
 */

# Generate workspace name if needed
locals {
  # Generate a default name if not provided
  workspace_name = var.name != null ? var.name : "${var.prefix}-${var.environment}-law-${var.region_abbv}"
}

# Create Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "this" {
  name                = local.workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  retention_in_days   = var.retention_in_days
  daily_quota_gb      = var.daily_quota_gb
  tags                = var.tags

  # Optional Internet ingestion and query
  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled

  # Since reservation_capacity_in_gb_per_day is not supported in the current provider version, 
  # we'll use a comment to document this instead
  # Note: In AzureRM provider 4.23.0, the reservation block is not supported
  # For capacity reservations, upgrade to a newer provider version and uncomment this block
}

# Create Log Analytics Solutions
resource "azurerm_log_analytics_solution" "this" {
  for_each = { for solution in var.solution_plans : solution.solution_name => solution }

  solution_name         = each.value.solution_name
  resource_group_name   = var.resource_group_name
  location              = var.location
  workspace_resource_id = azurerm_log_analytics_workspace.this.id
  workspace_name        = azurerm_log_analytics_workspace.this.name
  tags                  = var.tags

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/${each.value.solution_name}"
  }
}

# Create Diagnostic Settings for the Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = {
    for idx, setting in var.diagnostic_settings : idx => setting
  }

  name = each.value.name

  # Target Log Analytics workspace is either the current one or an external one
  target_resource_id = azurerm_log_analytics_workspace.this.id
  
  # Handle the special "self" case for log_analytics_workspace_id
  log_analytics_workspace_id = each.value.log_analytics_workspace_id == "self" ? azurerm_log_analytics_workspace.this.id : each.value.log_analytics_workspace_id

  # Configure logs - retention is handled by Log Analytics workspace settings
  dynamic "enabled_log" {
    for_each = each.value.enabled_log_categories
    content {
      category = enabled_log.value
      # Retention is now handled separately via azurerm_storage_management_policy
      # or by the workspace's retention_in_days setting
    }
  }

  # Configure metrics - retention is handled by Log Analytics workspace settings 
  dynamic "metric" {
    for_each = each.value.metric_categories
    content {
      category = metric.value
      enabled  = true
      # Retention is now handled separately via azurerm_storage_management_policy
      # or by the workspace's retention_in_days setting
    }
  }
}

# Create Linked Storage Account if specified
resource "azurerm_log_analytics_linked_storage_account" "this" {
  for_each = var.linked_storage_accounts

  data_source_type      = each.key
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.this.id
  storage_account_ids   = each.value
} 