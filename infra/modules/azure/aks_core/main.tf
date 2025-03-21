/**
 * # AKS Core Module
 *
 * This module creates the core AKS cluster with essential configuration,
 * focused solely on the main cluster resource without additional components.
 */

# Generate DNS prefix if not provided and cluster name for auto-generation
locals {
  # Generate a default name if not provided
  cluster_name = var.name != null ? var.name : "${var.prefix}-${var.environment}-aks-${var.region_abbv}"

  # Generate DNS prefix if not provided
  dns_prefix = var.dns_prefix != null ? var.dns_prefix : lower(replace(local.cluster_name, "-", ""))
}

# Create the AKS cluster
resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                      = local.cluster_name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  dns_prefix                = local.dns_prefix
  kubernetes_version        = var.kubernetes_version
  local_account_disabled    = var.local_account_disabled
  sku_tier                  = var.sku_tier
  workload_identity_enabled = var.workload_identity_enabled
  oidc_issuer_enabled       = var.oidc_issuer_enabled

  # Enable Azure Policy and cost analysis
  azure_policy_enabled  = true
  cost_analysis_enabled = true

  # Azure AD integration
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.azure_active_directory_role_based_access_control != null ? [1] : []

    content {
      admin_group_object_ids = var.azure_active_directory_role_based_access_control.admin_group_object_ids
      azure_rbac_enabled     = var.azure_active_directory_role_based_access_control.azure_rbac_enabled
    }
  }

  # System node pool configuration
  default_node_pool {
    name                 = var.default_nodepool_name
    node_count           = var.default_nodepool_count
    vm_size              = var.default_nodepool_vm_size
    max_pods             = var.default_nodepool_max_pods
    os_disk_size_gb      = var.default_nodepool_os_disk_size_gb
    node_labels          = var.default_nodepool_node_labels
    auto_scaling_enabled = var.default_nodepool_enable_auto_scaling
    min_count            = var.default_nodepool_enable_auto_scaling ? var.default_nodepool_min_count : null
    max_count            = var.default_nodepool_enable_auto_scaling ? var.default_nodepool_max_count : null
    vnet_subnet_id       = var.subnet_id
    tags                 = var.tags
  }

  # Network profile configuration - set to "none" to not install any CNI by default
  # Cilium will be installed separately after cluster creation
  network_profile {
    network_plugin    = var.network_plugin # Set to "none" to use Cilium
    network_policy    = var.network_policy # Set to null when using Cilium
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    pod_cidr          = var.pod_cidr
    outbound_type     = var.outbound_type
    load_balancer_sku = "standard"
  }

  # Configure Container Insights (OMS Agent)
  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id != null ? [1] : []
    
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  # Apply tags
  tags = merge(var.tags, {
    name = local.cluster_name
  })

  # Configure cluster identity
  dynamic "identity" {
    for_each = var.identity_type == "UserAssigned" ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.user_assigned_identity_id]
    }
  }

  dynamic "identity" {
    for_each = var.identity_type == "SystemAssigned" ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  # Ensure we have minimal output to make testing easy
  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      kubernetes_version,
      network_profile[0].pod_cidr
    ]
  }
}

# Automatically update local kubeconfig with cluster credentials
resource "null_resource" "update_kubeconfig" {
  count = var.create_kubeconfig ? 1 : 0

  triggers = {
    cluster_id = azurerm_kubernetes_cluster.aks_cluster.id
  }

  # Run the az aks get-credentials command to update the kubeconfig
  provisioner "local-exec" {
    command = "az aks get-credentials --name ${azurerm_kubernetes_cluster.aks_cluster.name} --resource-group ${var.resource_group_name} --overwrite-existing"
  }
}

# Create Diagnostic Settings for the AKS Cluster
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = length(var.diagnostic_settings) > 0 ? 1 : 0
  
  name               = var.diagnostic_settings[0].name
  target_resource_id = azurerm_kubernetes_cluster.aks_cluster.id
  log_analytics_workspace_id = var.diagnostic_settings[0].log_analytics_workspace_id

  # Configure logs for each category
  dynamic "enabled_log" {
    for_each = toset(var.diagnostic_settings[0].enabled_log_categories)
    
    content {
      category = enabled_log.value
      # Retention is now handled separately via azurerm_storage_management_policy
      # or by the Log Analytics workspace's retention_in_days setting
    }
  }

  # Configure metrics for each category
  dynamic "metric" {
    for_each = toset(var.diagnostic_settings[0].metric_categories)
    
    content {
      category = metric.value
      enabled  = true
      # Retention is now handled separately via azurerm_storage_management_policy
      # or by the Log Analytics workspace's retention_in_days setting
    }
  }
} 