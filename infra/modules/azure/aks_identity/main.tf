/**
 * # AKS Identity Module
 *
 * This module creates and configures user-assigned managed identities for AKS clusters and workloads.
 * It handles identity creation, role assignments, and federated credential setup.
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
  # Generate identity names if not provided
  aks_identity_name = var.aks_identity_name != null ? var.aks_identity_name : "${var.cluster_name}-identity"
  cert_manager_identity_name = var.cert_manager_identity_name != null ? var.cert_manager_identity_name : "${var.cluster_name}-cert-manager"
  cert_manager_federated_credential_name = var.cert_manager_federated_credential_name != null ? var.cert_manager_federated_credential_name : "${var.cluster_name}-cert-manager-fedcred"
  karpenter_identity_name = var.karpenter_identity_name != null ? var.karpenter_identity_name : "${var.cluster_name}-karpenter"
  karpenter_federated_credential_name = var.karpenter_federated_credential_name != null ? var.karpenter_federated_credential_name : "${var.cluster_name}-karpenter-fedcred"
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

resource "azurerm_federated_identity_credential" "cert_manager_federated_credential" {
  count               = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled && var.oidc_issuer_url != null ? 1 : 0
  name                = local.cert_manager_federated_credential_name
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.cert_manager_identity[0].id
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

resource "azurerm_user_assigned_identity" "karpenter_identity" {
  count               = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? 1 : 0
  name                = local.karpenter_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  
  tags = merge(var.tags, {
    name = local.karpenter_identity_name
  })
}

# Grant Karpenter the ability to manage VMs if node resource group ID is provided
resource "azurerm_role_assignment" "karpenter_vm_contributor" {
  count                = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled && var.node_resource_group_id != null ? 1 : 0
  scope                = var.node_resource_group_id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.karpenter_identity[0].principal_id
}

# Grant Karpenter the ability to manage networks if node resource group ID is provided
resource "azurerm_role_assignment" "karpenter_network_contributor" {
  count                = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled && var.node_resource_group_id != null ? 1 : 0
  scope                = var.node_resource_group_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.karpenter_identity[0].principal_id
}

# Grant Karpenter the ability to manage managed identities if node resource group ID is provided
resource "azurerm_role_assignment" "karpenter_managed_identity_operator" {
  count                = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled && var.node_resource_group_id != null ? 1 : 0
  scope                = var.node_resource_group_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.karpenter_identity[0].principal_id
}

resource "azurerm_federated_identity_credential" "karpenter_federated_credential" {
  count               = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled && var.oidc_issuer_url != null ? 1 : 0
  name                = local.karpenter_federated_credential_name
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.karpenter_identity[0].id
  subject             = "system:serviceaccount:karpenter:karpenter"
} 