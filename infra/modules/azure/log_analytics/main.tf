/**
 * # Azure Log Analytics Workspace Module
 *
 * This module creates an Azure Log Analytics Workspace with essential configuration 
 * for monitoring Azure Kubernetes Service (AKS) clusters.
 */

# Create the Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "this" {
  count               = var.create ? 1 : 0
  # Name will be provided by Terragrunt using the naming module if null
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  retention_in_days   = var.retention_in_days
  daily_quota_gb      = var.daily_quota_gb

  internet_ingestion_enabled = var.internet_ingestion_enabled
  internet_query_enabled     = var.internet_query_enabled
  
  tags = var.tags
}

# Install solution packs if specified
resource "azurerm_log_analytics_solution" "this" {
  for_each = var.create ? { for solution in var.solution_plans : solution.solution_name => solution } : {}

  solution_name         = each.value.solution_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.this[0].id
  workspace_name        = azurerm_log_analytics_workspace.this[0].name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/${each.value.solution_name}"
  }

  tags = var.tags
}

# Create diagnostic settings for the workspace itself if specified
# resource "azurerm_monitor_diagnostic_setting" "this" {
#   for_each = {
#     for idx, setting in var.diagnostic_settings : 
#     setting.name => setting
#   }

#   name                       = each.value.name
#   target_resource_id         = azurerm_log_analytics_workspace.this.id
#   log_analytics_workspace_id = each.value.log_analytics_workspace_id == "self" ? azurerm_log_analytics_workspace.this.id : each.value.log_analytics_workspace_id

#   # Configure logs for each category
#   dynamic "enabled_log" {
#     for_each = toset(each.value.enabled_log_categories)
    
#     content {
#       category = enabled_log.value
#     }
#   }

#   # Configure metrics for each category
#   dynamic "metric" {
#     for_each = toset(each.value.metric_categories)
    
#     content {
#       category = metric.value
#       enabled  = true
#     }
#   }
# }

# Create role assignments for the Log Analytics workspace
resource "azurerm_role_assignment" "this" {
  for_each = var.create ? { for idx, assignment in var.role_assignments : idx => assignment } : {}

  scope                = azurerm_log_analytics_workspace.this[0].id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  description          = each.value.description
} 