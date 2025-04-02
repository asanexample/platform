/**
 * Creates an Azure Monitor Workspace.
 */

resource "azurerm_monitor_workspace" "this" {
  # Name will be provided by Terragrunt using the naming module if null
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
} 