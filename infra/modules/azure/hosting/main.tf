/**
 * # Azure Hosting Module
 * 
 * This module deploys networking, storage, and key vault resources in a single resource group,
 * providing a complete hosting infrastructure for applications. It integrates these
 * components to ensure secure network access to resources.
 *
 * IMPORTANT: This module always uses the naming module for standardized resource naming.
 * The required parameters for naming are: stage and region_abbv. The optional parameters
 * are: prefix (defaults to "vip") and customer (for customer-specific resources).
 */

# Use naming module for standardized resource naming
module "naming" {
  source = "../naming"

  prefix      = var.prefix
  customer    = var.customer
  environment = var.environment
  region_abbv = var.region_abbv
}

locals {
  # Always use naming module outputs for resource names
  resource_group_name  = module.naming.resource_group
  vnet_name            = module.naming.virtual_network
  storage_account_name = module.naming.storage_account
  key_vault_name       = module.naming.key_vault
  aks_cluster_name     = module.naming.aks_cluster

  # Create a map of subnet names using the naming module
  subnet_name_map = {
    for subnet_key in keys(var.subnets) :
    subnet_key => "${module.naming.subnet}-${subnet_key}-${var.region_abbv}"
  }
}

# Create a single resource group for all resources
resource "azurerm_resource_group" "hosting_rg" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Deploy networking infrastructure
module "network" {
  source = "../networking"

  resource_group_name = azurerm_resource_group.hosting_rg.name
  location            = azurerm_resource_group.hosting_rg.location
  vnet_name           = local.vnet_name
  address_space       = var.address_space
  subnets             = var.subnets
  dns_servers         = var.dns_servers

  tags = var.tags
}

# Deploy storage with private network integration
module "storage_account" {
  source = "../storage_account"

  resource_group_name = azurerm_resource_group.hosting_rg.name
  location            = azurerm_resource_group.hosting_rg.location

  # Always use naming module for storage account name
  name = local.storage_account_name
  name_components = {
    # Default values for the storage module's internal reference
    prefix      = "tmp"
    environment = var.environment
    region_abbv = var.region_abbv
    instance    = "01"
  }

  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type

  # Configure network rules to only allow access from VNet
  network_rules = {
    default_action = var.storage_network_default_action
    bypass         = var.storage_network_bypass
    virtual_network_subnet_ids = [
      for subnet_name in var.storage_allowed_subnets :
      module.network.subnet_ids[subnet_name]
    ]
  }

  containers = var.storage_containers

  # Enable public access if needed
  allow_nested_items_to_be_public = var.storage_allow_public
  blob_public_access_enabled      = var.storage_allow_public

  # Configure CORS if needed
  cors_rules = var.storage_cors_rules

  tags = var.tags
}

# Deploy key vault with appropriate access policies and network settings
module "key_vault" {
  source = "../key_vault"
  count  = var.create_key_vault ? 1 : 0

  resource_group_name = azurerm_resource_group.hosting_rg.name
  location            = azurerm_resource_group.hosting_rg.location

  # Always use naming module for key vault name
  name = local.key_vault_name
  name_components = {
    prefix      = var.prefix
    environment = var.environment
    region_abbv = var.region_abbv
    instance    = "01"
  }

  # Key vault configuration
  enable_rbac_authorization   = var.key_vault_enable_rbac
  enabled_for_disk_encryption = var.key_vault_enable_disk_encryption
  purge_protection_enabled    = var.key_vault_purge_protection
  soft_delete_retention_days  = var.key_vault_retention_days
  sku_name                    = var.key_vault_sku

  # Network configuration
  public_network_access_enabled = var.key_vault_public_access

  # Configure network rules to only allow access from VNet
  network_acls = var.key_vault_allowed_subnets != null ? {
    default_action = "Deny"
    bypass         = "AzureServices"
    virtual_network_subnet_ids = [
      for subnet_name in var.key_vault_allowed_subnets :
      module.network.subnet_ids[subnet_name]
    ]
  } : null

  # Access policies (used only when RBAC is disabled)
  access_policies = var.key_vault_access_policies

  # Private endpoint configuration
  private_endpoint = var.key_vault_private_endpoint_subnet != "" ? {
    create    = true
    subnet_id = module.network.subnet_ids[var.key_vault_private_endpoint_subnet]
    # If DNS zone IDs are provided, use them
    private_dns_zone_ids = var.key_vault_private_dns_zone_ids
  } : {}

  tags = var.tags
}

# Create AKS cluster with the composite module
module "aks_cluster" {
  source = "../aks_cluster_composite"

  # Use create_resources to control whether AKS resources are created
  create_resources = var.create_aks_cluster

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  environment = var.environment
  region_abbv = var.region_abbv

  # Resource group and location
  resource_group_name = azurerm_resource_group.hosting_rg.name
  location            = var.location

  # Cluster configuration
  name               = var.aks_dns_prefix != null ? var.aks_dns_prefix : null
  kubernetes_version = var.aks_kubernetes_version
  sku_tier           = var.aks_sku_tier

  # Network configuration
  network_plugin      = var.aks_network_plugin
  network_plugin_mode = var.aks_network_plugin_mode
  network_policy      = var.aks_network_policy
  network_data_plane  = var.aks_network_data_plane
  pod_cidr            = var.aks_pod_cidr
  service_cidr        = var.aks_service_cidr
  dns_service_ip      = var.aks_dns_service_ip
  docker_bridge_cidr  = var.aks_docker_bridge_cidr

  # Subnet configuration
  subnet_id = var.aks_subnet_name != null && var.aks_subnet_name != "" ? module.network.subnet_ids[var.aks_subnet_name] : null

  # Network topology configuration
  use_network_topology     = var.aks_use_network_topology
  vnet_resource_group_name = var.resource_group_name
  network_topology_region  = startswith(var.location, "east") ? "eastus" : startswith(var.location, "west") ? "westus" : lower(replace(var.location, " ", ""))

  # AZ-specific subnet configuration if available
  availability_zones = var.aks_availability_zones
  az_subnet_ids = var.aks_az_subnet_names != null ? (
    length(coalesce(var.aks_az_subnet_names, {})) > 0 ? {
      for az, subnet_name in var.aks_az_subnet_names :
      az => module.network.subnet_ids[subnet_name]
    } : {}
  ) : {}

  # Identity and monitoring
  workload_identity_enabled  = var.aks_workload_identity_enabled
  oidc_issuer_enabled        = var.aks_oidc_issuer_enabled
  local_account_disabled     = var.aks_local_account_disabled
  log_analytics_workspace_id = var.aks_log_analytics_workspace_id

  # Private cluster settings
  private_cluster_enabled             = var.aks_private_cluster_enabled
  private_dns_zone_id                 = var.aks_private_dns_zone_id
  private_cluster_public_fqdn_enabled = var.aks_private_cluster_public_fqdn_enabled
  authorized_ip_ranges                = var.aks_authorized_ip_ranges

  tags = var.tags

  depends_on = [
    module.network
  ]
}

# Monitoring resources
module "monitoring" {
  count  = var.create_monitoring_resources ? 1 : 0
  source = "../monitoring"

  # Naming
  prefix      = var.prefix
  customer    = var.customer
  environment = var.environment
  region_abbv = var.region_abbv

  # Resource group and location
  resource_group_name = azurerm_resource_group.hosting_rg.name
  location            = var.location

  # Tags
  tags = var.tags
}

# Add more references as needed 