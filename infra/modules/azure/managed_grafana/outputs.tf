output "id" {
  description = "The ID of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.grafana.id
}

output "name" {
  description = "The name of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.grafana.name
}

output "endpoint" {
  description = "The endpoint URL of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.grafana.endpoint
}

output "principal_id" {
  description = "The principal ID of the system assigned identity of the Azure Managed Grafana instance"
  value       = azurerm_dashboard_grafana.grafana.identity[0].principal_id
} 