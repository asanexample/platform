/**
 * # Outputs for Azure Managed Grafana Module
 * 
 * This file defines all the outputs from the Azure Managed Grafana module.
 */

output "id" {
  description = "The ID of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.grafana.id
}

output "name" {
  description = "The name of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.grafana.name
}

output "resource_group_name" {
  description = "The name of the resource group where the Grafana instance is deployed"
  value       = azurerm_dashboard_grafana.grafana.resource_group_name
}

output "endpoint" {
  description = "The endpoint URL of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.grafana.endpoint
}

output "grafana_version" {
  description = "The version of Grafana being used"
  value       = azurerm_dashboard_grafana.grafana.grafana_version
}

output "identity" {
  description = "The identity of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.grafana.identity
} 