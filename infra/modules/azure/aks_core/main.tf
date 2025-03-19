/**
 * # AKS Core Module
 *
 * This module creates the core AKS cluster with essential configuration,
 * focused solely on the main cluster resource without additional components.
 * It uses the common naming module to ensure consistent naming across all resources.
 */

# Use the naming module to generate standardized names
module "naming" {
  source = "../naming"

  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv
}

# Generate DNS prefix if not provided
locals {
  dns_prefix = var.dns_prefix != null ? var.dns_prefix : lower(replace(module.naming.aks_cluster, "-", ""))
}

# Create the AKS cluster
resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                      = var.name != "" ? var.name : module.naming.aks_cluster
  location                  = var.location
  resource_group_name       = var.resource_group_name
  dns_prefix                = local.dns_prefix
  kubernetes_version        = var.kubernetes_version
  local_account_disabled    = var.local_account_disabled
  sku_tier                  = var.sku_tier
  workload_identity_enabled = var.workload_identity_enabled
  oidc_issuer_enabled       = var.oidc_issuer_enabled
  
  # Enable Azure Policy and cost analysis
  azure_policy_enabled      = true
  cost_analysis_enabled     = true
  
  # Apply tags
  tags = merge(var.tags, {
    name = var.name != "" ? var.name : module.naming.aks_cluster
  })

  # System node pool configuration - minimal required settings
  default_node_pool {
    name                = var.default_nodepool_name
    node_count          = var.default_nodepool_count
    vm_size             = var.default_nodepool_vm_size
    tags                = var.tags
  }

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
    ]
  }
} 