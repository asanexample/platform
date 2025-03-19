/**
 * # Azure Kubernetes Service (AKS) Cluster Module
 *
 * This module creates an Azure Kubernetes Service cluster with comprehensive
 * security, monitoring, and identity integrations. It follows the platform's
 * naming conventions and best practices for Kubernetes deployments.
 */

# Generate cluster name if not provided, using standard naming patterns
locals {
  # Generate cluster name if not provided using naming components
  aks_cluster_name = var.name != "" ? var.name : "${var.name_components.prefix}${var.name_components.environment}aks${var.name_components.region_abbv}"

  # Default identity names if not provided
  aks_identity_name = var.aks_identity_name != null ? var.aks_identity_name : "${local.aks_cluster_name}-identity"
  cert_manager_identity_name = var.cert_manager_identity_name != null ? var.cert_manager_identity_name : "${local.aks_cluster_name}-cert-manager"
  cert_manager_federated_credential_name = var.cert_manager_federated_credential_name != null ? var.cert_manager_federated_credential_name : "${local.aks_cluster_name}-cert-manager-fedcred"
  karpenter_identity_name = var.karpenter_identity_name != null ? var.karpenter_identity_name : "${local.aks_cluster_name}-karpenter"
  karpenter_federated_credential_name = var.karpenter_federated_credential_name != null ? var.karpenter_federated_credential_name : "${local.aks_cluster_name}-karpenter-fedcred"
  
  # Default diagnostic setting name if not provided
  diagnostic_setting_name = var.diagnostic_setting_name != null ? var.diagnostic_setting_name : "${local.aks_cluster_name}-diag"
  
  # Generate DNS prefix if not provided
  dns_prefix = var.dns_prefix != null ? var.dns_prefix : lower(local.aks_cluster_name)
}

# Create a user-assigned managed identity for the AKS cluster
resource "azurerm_user_assigned_identity" "aks_identity" {
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = local.aks_identity_name

  tags = merge(var.tags, {
    name = local.aks_identity_name
  })
}

# Create the AKS cluster
resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                         = local.aks_cluster_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  dns_prefix                   = local.dns_prefix
  kubernetes_version           = var.kubernetes_version
  local_account_disabled       = var.local_account_disabled
  sku_tier                     = var.sku_tier
  workload_identity_enabled    = var.workload_identity_enabled
  oidc_issuer_enabled          = var.oidc_issuer_enabled
  
  # Enable Azure Policy, cost analysis, and image cleaner
  azure_policy_enabled         = true
  cost_analysis_enabled        = true
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 24
  
  tags = merge(var.tags, {
    name = local.aks_cluster_name
  })

  # Configure monitoring metrics
  monitor_metrics {
    annotations_allowed = true
    labels_allowed      = true
  }

  # System node pool configuration
  default_node_pool {
    name                       = var.default_nodepool_name
    node_count                 = var.default_nodepool_count
    vm_size                    = var.default_nodepool_vm_size
    vnet_subnet_id             = var.nodepool_subnet_id
    zones                      = var.zones
    auto_scaling_enabled       = true
    min_count                  = var.default_nodepool_min_count
    max_count                  = var.default_nodepool_max_count
    temporary_name_for_rotation = "${var.default_nodepool_name}temp"
    host_encryption_enabled    = true
  }

  # Configure Azure RBAC for access control
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = var.azure_rbac_enabled
    admin_group_object_ids = var.admin_group_object_ids
  }

  # Configure cluster identity
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.aks_identity.id
    ]
  }

  # Configure kubelet identity
  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.aks_identity.client_id
    object_id                 = azurerm_user_assigned_identity.aks_identity.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.aks_identity.id
  }

  # Configure Log Analytics integration
  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  # Configure networking
  network_profile {
    network_plugin      = var.network_plugin
    network_plugin_mode = var.network_plugin_mode
    network_policy      = var.network_policy
    network_data_plane  = var.network_data_plane
  }

  # Configure private cluster settings
  private_cluster_enabled             = var.private_cluster_enabled
  private_dns_zone_id                 = var.private_cluster_enabled ? var.private_dns_zone_id : null
  private_cluster_public_fqdn_enabled = var.private_cluster_enabled ? var.private_cluster_public_fqdn_enabled : null

  # Configure API server access profile
  dynamic "api_server_access_profile" {
    for_each = [1]
    content {
      authorized_ip_ranges = var.private_cluster_enabled ? null : var.authorized_ip_ranges
    }
  }

  # Configure workload autoscaler profile
  workload_autoscaler_profile {
    keda_enabled                    = true
    vertical_pod_autoscaler_enabled = true
  }

  depends_on = [
    azurerm_role_assignment.aks_network_contributor,
    azurerm_role_assignment.aks_subnet_network_contributor,
  ]
}

# Fetch the private route table if specified
data "azurerm_route_table" "private" {
  count               = var.private_route_table_name != null && var.vnet_resource_group_name != null ? 1 : 0
  name                = var.private_route_table_name
  resource_group_name = var.vnet_resource_group_name
}

# Grant the AKS identity permissions to manage the route table
resource "azurerm_role_assignment" "aks_network_contributor" {
  count               = var.private_route_table_name != null && var.vnet_resource_group_name != null ? 1 : 0
  scope                = data.azurerm_route_table.private[0].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# Grant the AKS identity permissions to manage the subnet
resource "azurerm_role_assignment" "aks_subnet_network_contributor" {
  scope                = var.nodepool_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# Grant the AKS identity permissions to manage itself
resource "azurerm_role_assignment" "kubelet_managed_identity_operator" {
  scope                = azurerm_user_assigned_identity.aks_identity.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# Create an identity for cert-manager if workload identity is enabled
resource "azurerm_user_assigned_identity" "cert_manager_identity" {
  count               = var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  name                = local.cert_manager_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  
  tags = merge(var.tags, {
    name = local.cert_manager_identity_name
  })
}

# Create a federated identity credential for cert-manager
resource "azurerm_federated_identity_credential" "cert_manager_federated_credential" {
  count               = var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  name                = local.cert_manager_federated_credential_name
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.cert_manager_identity[0].id
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

# Create an identity for Karpenter if workload identity is enabled
resource "azurerm_user_assigned_identity" "karpenter_identity" {
  count               = var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  name                = local.karpenter_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  
  tags = merge(var.tags, {
    name = local.karpenter_identity_name
  })
}

# Grant Karpenter the ability to manage VMs
resource "azurerm_role_assignment" "karpenter_vm_contributor" {
  count               = var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  scope                = azurerm_kubernetes_cluster.aks_cluster.node_resource_group_id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.karpenter_identity[0].principal_id
}

# Grant Karpenter the ability to manage networks
resource "azurerm_role_assignment" "karpenter_network_contributor" {
  count               = var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  scope                = azurerm_kubernetes_cluster.aks_cluster.node_resource_group_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.karpenter_identity[0].principal_id
}

# Grant Karpenter the ability to manage managed identities
resource "azurerm_role_assignment" "karpenter_managed_identity_operator" {
  count               = var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  scope                = azurerm_kubernetes_cluster.aks_cluster.node_resource_group_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.karpenter_identity[0].principal_id
}

# Create a federated identity credential for Karpenter
resource "azurerm_federated_identity_credential" "karpenter_federated_credential" {
  count               = var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  name                = local.karpenter_federated_credential_name
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.karpenter_identity[0].id
  subject             = "system:serviceaccount:karpenter:karpenter"
}

# Create an application node pool if enabled
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  count                   = var.create_app_nodepool ? 1 : 0
  name                    = var.app_nodepool_name
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.aks_cluster.id
  vm_size                 = var.app_nodepool_vm_size
  node_count              = var.app_nodepool_count
  vnet_subnet_id          = var.nodepool_subnet_id
  host_encryption_enabled = true
  auto_scaling_enabled    = true
  min_count               = var.app_nodepool_min_count
  max_count               = var.app_nodepool_max_count
  zones                   = var.zones
  
  tags = merge(var.tags, {
    name = var.app_nodepool_name
  })
}

# Set up diagnostic settings for the AKS cluster
resource "azurerm_monitor_diagnostic_setting" "aks_cluster_diagnostic_setting" {
  name                       = local.diagnostic_setting_name
  target_resource_id         = azurerm_kubernetes_cluster.aks_cluster.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Enable supported log categories
  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_log {
    category = "cloud-controller-manager"
  }

  enabled_log {
    category = "guard"
  }

  enabled_log {
    category = "csi-azuredisk-controller"
  }

  enabled_log {
    category = "csi-azurefile-controller"
  }

  enabled_log {
    category = "csi-snapshot-controller"
  }

  # Enable all metrics
  metric {
    category = "AllMetrics"
  }
}

# Set up a data collection endpoint for Prometheus metrics
resource "azurerm_monitor_data_collection_endpoint" "aks_dce" {
  name                = substr("MSProm-${var.location}-${local.aks_cluster_name}", 0, min(44, length("MSProm-${var.location}-${local.aks_cluster_name}")))
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
}

# Set up a data collection rule for Prometheus metrics
resource "azurerm_monitor_data_collection_rule" "aks_dcr" {
  name                        = substr("MSProm-${var.location}-${local.aks_cluster_name}", 0, min(64, length("MSProm-${var.location}-${local.aks_cluster_name}")))
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.aks_dce.id
  kind                        = "Linux"

  destinations {
    monitor_account {
      monitor_account_id = var.monitor_workspace_id
      name               = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
    }
  }

  description = "DCR for Azure Monitor Metrics Profile (Managed Prometheus)"
  depends_on = [
    azurerm_monitor_data_collection_endpoint.aks_dce
  ]
}

# Associate the data collection rule with the AKS cluster
resource "azurerm_monitor_data_collection_rule_association" "aks_dcr_association" {
  name                    = "AKSDCRAssociation"
  target_resource_id      = azurerm_kubernetes_cluster.aks_cluster.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.aks_dcr.id
  description             = "Association of the data collection rule for Prometheus metrics with the AKS Cluster."
}

# Grant the AKS identity permissions to publish metrics
resource "azurerm_role_assignment" "remote_write_monitoring_metrics_publisher_role_assignment" {
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
  role_definition_name = "Monitoring Metrics Publisher"
  scope                = azurerm_monitor_data_collection_rule.aks_dcr.id
}

# Set up container insights for the AKS cluster
resource "azurerm_monitor_data_collection_rule" "container_insights_dcr" {
  name                = "MSCI-${var.location}-${local.aks_cluster_name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "${local.aks_cluster_name}-workspace"
    }
  }

  data_flow {
    streams      = var.streams
    destinations = ["${local.aks_cluster_name}-workspace"]
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["${local.aks_cluster_name}-workspace"]
  }

  data_sources {
    syslog {
      streams        = ["Microsoft-Syslog"]
      facility_names = var.syslog_facilities
      log_levels     = var.syslog_levels
      name           = "sysLogsDataSource"
    }

    extension {
      streams        = var.streams
      extension_name = "ContainerInsights"
      extension_json = jsonencode({
        "dataCollectionSettings" : {
          "interval" : var.data_collection_interval,
          "namespaceFilteringMode" : var.namespace_filtering_mode_for_data_collection,
          "namespaces" : var.namespaces_for_data_collection
          "enableContainerLogV2" : var.enableContainerLogV2
        }
      })
      name = "ContainerInsightsExtension"
    }
  }

  description = "DCR for Azure Monitor Container Insights"
}

# Associate container insights with the AKS cluster
resource "azurerm_monitor_data_collection_rule_association" "container_insights_dcra" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.aks_cluster.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights_dcr.id
  description             = "Association of container insights data collection rule. Deleting this association will break the data collection for this AKS Cluster."
} 