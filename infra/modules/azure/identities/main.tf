/**
 * # Azure Identities Module
 *
 * This module provides a unified approach to managing Azure identities for various workloads, 
 * particularly for AKS clusters. It handles:
 * - Creating the AKS cluster identity
 * - Creating workload identities with optional role assignments
 * - Setting up federated credential configurations
 * - Managing role assignments for networking, route tables, and other Azure resources
 *
 * This module replaces the previous two-phase approach with a unified system where all identities
 * are managed in one place, with clear dependencies.
 */

# Use the naming module to generate standardized names
module "naming" {
  source = "../naming"

  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv
}

locals {
  # AKS identity name - use provided or generate based on cluster name
  aks_identity_name = var.aks_identity_name != null ? var.aks_identity_name : "${var.cluster_name}-identity"

  # Create a map of workload identities with appropriate configuration
  workload_identities_map = {
    for name, config in var.workload_identities : name => {
      name            = config.name != null ? config.name : "${var.cluster_name}-${name}"
      namespace       = config.namespace
      service_account = config.service_account
      roles           = config.roles
    }
  }

  # Normalize AKS OIDC information to handle null values gracefully
  aks_oidc_issuer_url    = var.aks_oidc_issuer_url
  node_resource_group_id = var.node_resource_group_id

  # Determine if we can create federated credentials based on OIDC URL availability
  can_create_federated_credentials = var.enable_workload_identity && local.aks_oidc_issuer_url != null
}

# =============================================================================
# AKS CLUSTER IDENTITY
# =============================================================================

# Create a user-assigned managed identity for the AKS cluster
resource "azurerm_user_assigned_identity" "aks_identity" {
  count               = var.create_aks_identity ? 1 : 0
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = local.aks_identity_name

  tags = merge(var.tags, {
    name = local.aks_identity_name
  })
}

# Fetch the private route table if specified for network permissions
data "azurerm_route_table" "private" {
  count               = var.private_route_table_name != null && var.vnet_resource_group_name != null ? 1 : 0
  name                = var.private_route_table_name
  resource_group_name = var.vnet_resource_group_name
}

# Grant the AKS identity permissions to manage the route table
resource "azurerm_role_assignment" "aks_network_contributor" {
  count                = var.create_aks_identity && var.private_route_table_name != null && var.vnet_resource_group_name != null ? 1 : 0
  scope                = data.azurerm_route_table.private[0].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity[0].principal_id
}

# Grant the AKS identity permissions to manage the subnet if provided
resource "azurerm_role_assignment" "aks_subnet_network_contributor" {
  count                = var.create_aks_identity && var.subnet_id != null ? 1 : 0
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity[0].principal_id
}

# Grant the AKS identity permissions to manage itself
resource "azurerm_role_assignment" "aks_managed_identity_operator" {
  count                = var.create_aks_identity ? 1 : 0
  scope                = azurerm_user_assigned_identity.aks_identity[0].id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.aks_identity[0].principal_id
}

# =============================================================================
# WORKLOAD IDENTITIES
# =============================================================================

# Create user-assigned identities for workloads
resource "azurerm_user_assigned_identity" "workload_identities" {
  for_each            = var.enable_workload_identity ? var.workload_identities : {}
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = each.value.name != null ? each.value.name : "${var.cluster_name}-${each.key}"

  tags = merge(var.tags, {
    name = each.value.name != null ? each.value.name : "${var.cluster_name}-${each.key}"
  })
}

# Create federated credentials for workloads if OIDC is available
resource "azurerm_federated_identity_credential" "workload_credentials" {
  for_each = {
    for name, config in var.workload_identities : name => config
    if local.can_create_federated_credentials
  }

  name                = "${each.value.name != null ? each.value.name : "${var.cluster_name}-${each.key}"}-fedcred"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = local.aks_oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.workload_identities[each.key].id
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

# =============================================================================
# ROLE ASSIGNMENTS FOR WORKLOADS
# =============================================================================

# Assign roles to workload identities on the node resource group
resource "azurerm_role_assignment" "workload_node_rg_roles" {
  for_each = {
    for item in flatten([
      for name, config in var.workload_identities : [
        for role in config.roles : {
          workload_name = name
          role_name     = role
        }
      ]
    ]) : "${item.workload_name}-${item.role_name}" => item
    if local.node_resource_group_id != null
  }

  scope                = local.node_resource_group_id
  role_definition_name = each.value.role_name
  principal_id         = azurerm_user_assigned_identity.workload_identities[each.value.workload_name].principal_id
}

# Add additional role assignments for workloads as needed
# For example, resource-specific role assignments would go here 