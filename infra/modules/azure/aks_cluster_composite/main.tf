/**
 * # AKS Cluster Composite Module
 *
 * This module creates a complete AKS cluster solution by integrating multiple specialized modules,
 * following the principles of separation of concerns and modularity.
 */

# Create the core AKS cluster
module "aks_core" {
  source = "../aks_core"

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv
  name        = var.name

  # Resource details
  resource_group_name = var.resource_group_name
  location           = var.location
  dns_prefix         = var.dns_prefix
  
  # Cluster configuration
  kubernetes_version       = var.kubernetes_version
  local_account_disabled   = var.local_account_disabled
  sku_tier                 = var.sku_tier
  workload_identity_enabled = var.workload_identity_enabled
  oidc_issuer_enabled       = var.oidc_issuer_enabled
  
  # Default node pool
  default_nodepool_name    = var.default_nodepool_name
  default_nodepool_vm_size = var.default_nodepool_vm_size
  default_nodepool_count   = var.default_nodepool_count
  
  # Identity
  identity_type           = var.identity_type
  user_assigned_identity_id = var.user_assigned_identity_id

  # Tagging
  tags = var.tags
}

# Create additional node pools
module "aks_node_pools" {
  source = "../aks_node_pools"
  
  # Only create if app node pool is enabled
  count = var.app_node_pool_enabled ? 1 : 0

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv

  # Reference to the core AKS cluster
  aks_cluster_id = module.aks_core.id
  
  # App node pool configuration
  app_node_pool_enabled     = var.app_node_pool_enabled
  app_node_pool_vm_size     = var.app_node_pool_vm_size
  app_node_pool_node_count  = var.app_node_pool_node_count
  app_node_pool_max_pods    = var.app_node_pool_max_pods
  app_node_pool_os_disk_size_gb = var.app_node_pool_os_disk_size_gb
  
  # Auto-scaling configuration
  app_node_pool_enable_auto_scaling = var.app_node_pool_enable_auto_scaling
  app_node_pool_min_count  = var.app_node_pool_min_count
  app_node_pool_max_count  = var.app_node_pool_max_count
  
  # Node labels
  app_node_pool_node_labels = var.app_node_pool_node_labels

  # Tagging
  tags = var.tags
} 