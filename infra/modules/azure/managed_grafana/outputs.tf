/**
 * # Outputs for Azure Managed Grafana Module
 *
 * This file defines all the outputs from the Azure Managed Grafana module.
 */

output "id" {
  description = "The ID of the Azure Managed Grafana instance"
  value       = var.create ? azurerm_dashboard_grafana.grafana[0].id : null
}

output "name" {
  description = "The name of the Azure Managed Grafana instance"
  value       = var.create ? azurerm_dashboard_grafana.grafana[0].name : null
}

output "resource_group_name" {
  description = "The name of the resource group where the Grafana instance is deployed"
  value       = var.create ? azurerm_dashboard_grafana.grafana[0].resource_group_name : null
}

output "endpoint" {
  description = "The endpoint URL of the Azure Managed Grafana instance"
  value       = var.create ? azurerm_dashboard_grafana.grafana[0].endpoint : null
}

output "grafana_version" {
  description = "The version of Grafana being used"
  value       = var.create ? azurerm_dashboard_grafana.grafana[0].grafana_version : null
}

output "identity" {
  description = "The identity of the Azure Managed Grafana instance"
  value       = var.create ? azurerm_dashboard_grafana.grafana[0].identity : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
} 