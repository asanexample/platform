/**
 * # Container Insights DCR Module
 *
 * This module creates Data Collection Rules (DCR) for Container Insights to work with
 * Azure Monitor Agent (AMA) instead of the deprecated Log Analytics Agent (MMA/OMS).
 * It supports the new Azure Monitor agent-based container monitoring.
 */

resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "MSCI-${var.location}-${var.cluster_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  
  destinations {
    log_analytics {
      name                = "LogAnalyticsWorkspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = var.data_streams
    destinations = ["LogAnalyticsWorkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = var.data_streams
    }
  }

  description = "Container Insights data collection rule for AKS cluster: ${var.cluster_name}"
  tags        = var.tags
}

# Associate the DCR with the AKS cluster
resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "${var.cluster_name}-container-insights"
  target_resource_id      = var.cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
  description             = "Association between AKS cluster and Container Insights data collection rule"
} 