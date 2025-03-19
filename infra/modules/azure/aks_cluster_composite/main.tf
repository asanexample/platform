/**
 * # AKS Cluster Composite Module
 *
 * This module creates a complete AKS cluster solution by integrating multiple specialized modules,
 * following the principles of separation of concerns and modularity.
 */

# Set up networking topology based on allocations.csv
locals {
  # Use the provided subnet_id by default
  primary_subnet_id = var.subnet_id
  
  # Just pass through the provided values
  service_cidr = var.service_cidr
  pod_cidr = var.pod_cidr
  dns_service_ip = var.dns_service_ip
}

# Create identity resources for the AKS cluster
module "aks_identity" {
  source = "../aks_identity"

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv

  # Resource group and location
  resource_group_name = var.resource_group_name
  location           = var.location
  
  # Cluster information
  cluster_name = var.name
  
  # Identity configuration
  create_workload_identities = true
  workload_identity_enabled = var.workload_identity_enabled
  oidc_issuer_enabled      = var.oidc_issuer_enabled
  
  # Tagging
  tags = var.tags
}

# Create networking resources for the AKS cluster
module "aks_networking" {
  source = "../aks_networking"

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv

  # Resource group and location
  resource_group_name = var.resource_group_name
  location           = var.location
  
  # Cluster information
  cluster_name = var.name
  node_resource_group = var.resource_group_name # Will be updated after cluster creation
  
  # Network configuration
  network_plugin     = var.network_plugin
  network_plugin_mode = var.network_plugin_mode
  network_policy     = var.network_policy
  network_data_plane = var.network_data_plane
  pod_cidr          = local.pod_cidr
  service_cidr      = local.service_cidr
  dns_service_ip    = local.dns_service_ip
  docker_bridge_cidr = var.docker_bridge_cidr
  subnet_id         = local.primary_subnet_id
  private_cluster_enabled = var.private_cluster_enabled
  private_dns_zone_id = var.private_dns_zone_id
  private_cluster_public_fqdn_enabled = var.private_cluster_public_fqdn_enabled
  authorized_ip_ranges = var.authorized_ip_ranges
  
  # Tagging
  tags = var.tags
}

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
  
  # Identity - use the identity created by the identity module
  identity_type           = "UserAssigned"
  user_assigned_identity_id = module.aks_identity.aks_identity_id

  # Tagging
  tags = var.tags
  
  # Dependencies
  depends_on = [
    module.aks_identity,
    module.aks_networking
  ]
}

# Set up monitoring for the AKS cluster
module "aks_monitoring" {
  source = "../aks_monitoring"
  
  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv
  
  # Resource group and location
  resource_group_name = var.resource_group_name
  location           = var.location
  
  # Cluster information
  cluster_name = module.aks_core.name
  cluster_id   = module.aks_core.id
  
  # Log Analytics workspace
  log_analytics_workspace_id = var.log_analytics_workspace_id
  
  # Tagging
  tags = var.tags
  
  # Dependencies
  depends_on = [
    module.aks_core
  ]
}

# Update AKS identity module with OIDC issuer URL and node resource group
module "aks_identity_update" {
  source = "../aks_identity"

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv

  # Resource group and location
  resource_group_name = var.resource_group_name
  location           = var.location
  
  # Cluster information
  cluster_name = module.aks_core.name
  
  # Pass OIDC issuer URL from core module
  create_workload_identities = true
  workload_identity_enabled = var.workload_identity_enabled
  oidc_issuer_enabled      = var.oidc_issuer_enabled
  oidc_issuer_url         = module.aks_core.oidc_issuer_url
  node_resource_group_id  = module.aks_core.node_resource_group_id
  subnet_id              = var.subnet_id
  
  # Tagging
  tags = var.tags
  
  # Use existing identity
  aks_identity_name = module.aks_identity.aks_identity_id
  
  # Dependencies
  depends_on = [
    module.aks_core
  ]
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
  app_node_pool_name        = var.app_node_pool_name
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
  
  # Dependencies
  depends_on = [
    module.aks_core
  ]
} 