/**
 * # AKS Identity Module
 *
 * This module creates and configures user-assigned managed identities for AKS clusters and workloads.
 * It handles identity creation, role assignments, and federated credential setup.
 */

locals {
  # Generate identity names if not provided
  aks_identity_name                      = var.aks_identity_name != null ? var.aks_identity_name : "${var.prefix}-${var.stage}-aks-identity"
  cert_manager_identity_name             = var.cert_manager_identity_name != null ? var.cert_manager_identity_name : "${var.prefix}-${var.stage}-cert-manager"
  cert_manager_federated_credential_name = var.cert_manager_federated_credential_name != null ? var.cert_manager_federated_credential_name : "${var.prefix}-${var.stage}-cert-manager-fedcred"
  karpenter_identity_name                = var.karpenter_identity_name != null ? var.karpenter_identity_name : "${var.prefix}-${var.stage}-karpenter"
  karpenter_federated_credential_name    = var.karpenter_federated_credential_name != null ? var.karpenter_federated_credential_name : "${var.prefix}-${var.stage}-karpenter-fedcred"
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

# Fetch the private route table if specified
data "azurerm_route_table" "private" {
  count               = var.private_route_table_name != null && var.vnet_resource_group_name != null ? 1 : 0
  name                = var.private_route_table_name
  resource_group_name = var.vnet_resource_group_name
}

# Grant the AKS identity permissions to manage the route table
resource "azurerm_role_assignment" "aks_network_contributor" {
  count                = var.private_route_table_name != null && var.vnet_resource_group_name != null ? 1 : 0
  scope                = data.azurerm_route_table.private[0].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# Grant the AKS identity permissions to manage the subnet if provided
resource "azurerm_role_assignment" "aks_subnet_network_contributor" {
  count                = var.subnet_id != null ? 1 : 0
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# Grant the AKS identity permissions to manage itself
resource "azurerm_role_assignment" "kubelet_managed_identity_operator" {
  scope                = azurerm_user_assigned_identity.aks_identity.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# Create workload identities if enabled
resource "azurerm_user_assigned_identity" "cert_manager_identity" {
  count               = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  name                = local.cert_manager_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = merge(var.tags, {
    name = local.cert_manager_identity_name
  })
}

# Note: Federated credentials require the OIDC issuer URL from the AKS cluster,
# which is only available after the cluster is created. Use this module with
# the two-phase deployment approach to handle this dependency.

resource "azurerm_user_assigned_identity" "karpenter_identity" {
  count               = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  name                = local.karpenter_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = merge(var.tags, {
    name = local.karpenter_identity_name
  })
}

# Note: Role assignments and federated credentials for workloads require
# the AKS cluster to be created first. Use this module with the two-phase
# deployment approach to handle this dependency. 