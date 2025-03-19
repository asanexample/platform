/**
 * Outputs for the AKS Monitoring module
 */

output "diagnostic_setting_id" {
  description = "The ID of the diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.aks_cluster_diagnostic_setting.id
}

output "prometheus_dce_id" {
  description = "The ID of the Prometheus data collection endpoint"
  value       = var.enable_prometheus ? azurerm_monitor_data_collection_endpoint.aks_dce[0].id : null
}

output "prometheus_dcr_id" {
  description = "The ID of the Prometheus data collection rule"
  value       = var.enable_prometheus ? azurerm_monitor_data_collection_rule.aks_dcr[0].id : null
}

output "container_insights_dcr_id" {
  description = "The ID of the Container Insights data collection rule"
  value       = var.enable_container_insights ? azurerm_monitor_data_collection_rule.container_insights_dcr[0].id : null
}

output "diagnostic_setting_name" {
  description = "The name of the diagnostic setting"
  value       = local.diagnostic_setting_name
}

output "prometheus_dce_name" {
  description = "The name of the Prometheus data collection endpoint"
  value       = var.enable_prometheus ? local.prometheus_dce_name : null
}

output "prometheus_dcr_name" {
  description = "The name of the Prometheus data collection rule"
  value       = var.enable_prometheus ? local.prometheus_dcr_name : null
}

output "container_insights_dcr_name" {
  description = "The name of the Container Insights data collection rule"
  value       = var.enable_container_insights ? local.container_insights_dcr_name : null
} 