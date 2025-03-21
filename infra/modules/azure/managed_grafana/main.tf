/**
 * # Azure Managed Grafana Module
 *
 * This module creates an Azure Managed Grafana instance and configures it to work with 
 * Azure Managed Prometheus for AKS monitoring.
 */

resource "azurerm_dashboard_grafana" "grafana" {
  name                              = var.name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  api_key_enabled                   = var.api_key_enabled
  deterministic_outbound_ip_enabled = var.deterministic_outbound_ip_enabled
  public_network_access_enabled     = var.public_network_access_enabled
  zone_redundancy_enabled           = var.zone_redundancy_enabled
  grafana_major_version             = var.grafana_major_version

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = var.prometheus_workspace_id
  }

  tags = var.tags
}

# Assign Grafana Admin role to the specified Azure AD groups
resource "azurerm_role_assignment" "grafana_admin" {
  count                = length(var.admin_group_object_ids)
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.admin_group_object_ids[count.index]
} 