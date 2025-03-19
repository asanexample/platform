/**
 * # AKS Cluster Composite Module
 *
 * This module combines various specialized AKS modules to create a complete solution:
 * - Identities for AKS and workloads
 * - AKS networking configuration
 * - Core AKS cluster
 * - Node pools
 */

locals {
  # Determine subnet ID based on network topology or direct input
  use_topology_condition = var.use_network_topology && var.vnet_resource_group_name != null && var.network_topology_region != null
  primary_subnet_id      = local.use_topology_condition ? "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.vnet_resource_group_name}/providers/Microsoft.Network/virtualNetworks/${var.network_topology_region}-spoke-vnet/subnets/${var.network_topology_region}-spoke-aks-subnet" : var.subnet_id

  # Set up pod and service CIDR values
  pod_cidr       = var.pod_cidr
  service_cidr   = var.service_cidr
  dns_service_ip = var.dns_service_ip != "" ? var.dns_service_ip : cidrhost(var.service_cidr, 10)
}

# Get current Azure subscription information
data "azurerm_client_config" "current" {}

# Create identity resources for the AKS cluster and workloads
module "identities" {
  source = "../identities"
  count  = var.create_resources ? 1 : 0

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv

  # Resource group and location
  resource_group_name = var.resource_group_name
  location            = var.location

  # Cluster information
  cluster_name = var.name

  # Identity configuration
  create_aks_identity      = true
  enable_workload_identity = var.workload_identity_enabled

  # Disable federated credentials and role assignments in first phase
  create_federated_credentials = false
  create_role_assignments      = false

  # Network configuration
  vnet_resource_group_name = var.vnet_resource_group_name
  private_route_table_name = var.private_route_table_name
  subnet_id                = local.primary_subnet_id

  # Tagging
  tags = var.tags
}

# Create networking resources for the AKS cluster
module "aks_networking" {
  source = "../aks_networking"
  count  = var.create_resources ? 1 : 0

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv

  # Resource group and location
  resource_group_name = var.resource_group_name
  location            = var.location

  # Cluster information
  cluster_name        = var.name
  node_resource_group = var.resource_group_name

  # Network configuration
  network_plugin                      = var.network_plugin
  network_plugin_mode                 = var.network_plugin_mode
  network_policy                      = var.network_policy
  network_data_plane                  = var.network_data_plane
  pod_cidr                            = local.pod_cidr
  service_cidr                        = local.service_cidr
  dns_service_ip                      = local.dns_service_ip
  docker_bridge_cidr                  = var.docker_bridge_cidr
  subnet_id                           = local.primary_subnet_id
  private_cluster_enabled             = var.private_cluster_enabled
  private_dns_zone_id                 = var.private_dns_zone_id
  private_cluster_public_fqdn_enabled = var.private_cluster_public_fqdn_enabled
  authorized_ip_ranges                = var.authorized_ip_ranges

  # Tagging
  tags = var.tags
}

# Create the core AKS cluster
module "aks_core" {
  source = "../aks_core"
  count  = var.create_resources ? 1 : 0

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv
  name        = var.name

  # Resource details
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.dns_prefix

  # Cluster configuration
  kubernetes_version        = var.kubernetes_version
  local_account_disabled    = var.local_account_disabled
  sku_tier                  = var.sku_tier
  workload_identity_enabled = var.workload_identity_enabled
  oidc_issuer_enabled       = var.oidc_issuer_enabled

  # Default node pool
  default_nodepool_name    = var.default_nodepool_name
  default_nodepool_vm_size = var.default_nodepool_vm_size
  default_nodepool_count   = var.default_nodepool_count

  # Identity - use the identity created by the identities module
  identity_type             = "UserAssigned"
  user_assigned_identity_id = module.identities[0].aks_identity_id

  # Network profile
  network_plugin     = module.aks_networking[0].network_plugin
  network_policy     = module.aks_networking[0].network_policy
  pod_cidr           = module.aks_networking[0].pod_cidr
  service_cidr       = module.aks_networking[0].service_cidr
  dns_service_ip     = module.aks_networking[0].dns_service_ip
  docker_bridge_cidr = module.aks_networking[0].docker_bridge_cidr
  subnet_id          = module.aks_networking[0].subnet_id

  # Private cluster configuration
  private_cluster_enabled = module.aks_networking[0].private_cluster_enabled
  private_dns_zone_id     = module.aks_networking[0].private_dns_zone_id

  # Tagging
  tags = var.tags
}

# Set up workload identities with the OIDC issuer URL from the cluster
module "workload_identity_setup" {
  source = "../identities"
  count  = var.create_resources && var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv

  # Resource group and location
  resource_group_name = var.resource_group_name
  location            = var.location

  # Cluster information
  cluster_name = module.aks_core[0].name

  # AKS Identity - don't create, use the existing one
  create_aks_identity = false

  # Workload identity configuration
  enable_workload_identity = true
  aks_oidc_issuer_url      = module.aks_core[0].oidc_issuer_url
  node_resource_group_id   = module.aks_core[0].node_resource_group_id

  # Enable federated credentials and role assignments in second phase
  create_federated_credentials = true
  create_role_assignments      = true

  # Configure workload identities
  workload_identities = {
    "cert-manager" = {
      namespace       = "cert-manager"
      service_account = "cert-manager"
      roles           = ["DNS Zone Contributor"]
    },
    "karpenter" = {
      namespace       = "karpenter"
      service_account = "karpenter"
      roles           = ["Virtual Machine Contributor", "Network Contributor"]
    }
  }

  # Tagging
  tags = var.tags

  # Dependencies
  depends_on = [
    module.aks_core
  ]
}

# Create the app node pool if enabled
module "aks_node_pools" {
  source = "../aks_node_pools"
  count  = var.create_resources && var.app_node_pool_enabled ? 1 : 0

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv

  # AKS cluster reference
  aks_cluster_id = module.aks_core[0].id

  # App node pool configuration
  app_node_pool_enabled             = true
  app_node_pool_name                = var.app_node_pool_name
  app_node_pool_vm_size             = var.app_node_pool_vm_size
  app_node_pool_node_count          = var.app_node_pool_node_count
  app_node_pool_max_pods            = var.app_node_pool_max_pods
  app_node_pool_os_disk_size_gb     = var.app_node_pool_os_disk_size_gb
  app_node_pool_enable_auto_scaling = var.app_node_pool_enable_auto_scaling
  app_node_pool_min_count           = var.app_node_pool_min_count
  app_node_pool_max_count           = var.app_node_pool_max_count
  app_node_pool_node_labels         = var.app_node_pool_node_labels

  # Tagging
  tags = var.tags

  # Dependencies
  depends_on = [
    module.aks_core
  ]
} 