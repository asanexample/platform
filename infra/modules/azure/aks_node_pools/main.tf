/**
 * # AKS Node Pools Module
 *
 * This module creates additional node pools for an existing AKS cluster,
 * separating node pool management from the core cluster configuration.
 */

# Use the naming module to generate standardized names
module "naming" {
  source = "../naming"

  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv
}

# Create application node pool if enabled
resource "azurerm_kubernetes_cluster_node_pool" "app_node_pool" {
  count = var.app_node_pool_enabled ? 1 : 0

  # Use standard naming convention from naming module
  name                  = module.naming.aks_node_pool
  kubernetes_cluster_id = var.aks_cluster_id
  vm_size               = var.app_node_pool_vm_size
  node_count            = var.app_node_pool_enable_auto_scaling ? null : var.app_node_pool_node_count
  
  # Availability zones for resilience
  zones = var.app_node_pool_availability_zones
  
  # Node pool configuration
  max_pods        = var.app_node_pool_max_pods
  os_disk_size_gb = var.app_node_pool_os_disk_size_gb
  os_disk_type    = var.app_node_pool_os_disk_type
  mode            = var.app_node_pool_mode
  node_labels     = var.app_node_pool_node_labels
  node_taints     = var.app_node_pool_node_taints
  
  # Auto-scaling configuration
  enable_auto_scaling = var.app_node_pool_enable_auto_scaling
  min_count           = var.app_node_pool_enable_auto_scaling ? var.app_node_pool_min_count : null
  max_count           = var.app_node_pool_enable_auto_scaling ? var.app_node_pool_max_count : null
  
  # Apply tags
  tags = var.tags

  # Ensure changes to certain properties are handled properly
  lifecycle {
    ignore_changes = [
      # Ignore changes to node_count if auto scaling is enabled
      node_count
    ]
  }
} 