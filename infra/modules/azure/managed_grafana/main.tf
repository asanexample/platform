/**
 * # Azure Managed Grafana Module
 *
 * This module creates an Azure Managed Grafana instance with Microsoft Entra (Azure AD) integration 
 * and Prometheus workspace connections.
 */

# Create the Grafana Dashboard
resource "azurerm_dashboard_grafana" "grafana" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  api_key_enabled               = var.api_key_enabled
  deterministic_outbound_ip_enabled = var.deterministic_outbound_ip_enabled
  public_network_access_enabled = var.public_network_access_enabled
  zone_redundancy_enabled       = var.zone_redundancy_enabled
  grafana_major_version         = var.grafana_major_version
  auto_generated_domain_name_label_scope = var.auto_generated_domain_name_label_scope
  identity {
    type = "SystemAssigned"
  }

  # Add Prometheus workspace integration
  dynamic "azure_monitor_workspace_integrations" {
    for_each = var.prometheus_workspace_id != null ? [1] : []
    content {
      resource_id = var.prometheus_workspace_id
    }
  }

  tags = var.tags
}

# Create role assignments for admin groups
resource "azurerm_role_assignment" "grafana_admin_groups" {
  for_each = toset(var.admin_group_object_ids)

  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = each.value
  principal_type       = "Group"
}

# Create role assignments for admin users
resource "azurerm_role_assignment" "grafana_admin_users" {
  for_each = toset(var.admin_user_object_ids)

  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = each.value
  principal_type       = "User"
} 