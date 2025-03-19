/**
 * Outputs for the AKS Identity module
 */

output "aks_identity_id" {
  description = "The ID of the AKS cluster identity"
  value       = azurerm_user_assigned_identity.aks_identity.id
}

output "aks_identity_principal_id" {
  description = "The principal ID of the AKS cluster identity"
  value       = azurerm_user_assigned_identity.aks_identity.principal_id
}

output "aks_identity_client_id" {
  description = "The client ID of the AKS cluster identity"
  value       = azurerm_user_assigned_identity.aks_identity.client_id
}

output "cert_manager_identity_id" {
  description = "The ID of the cert-manager identity"
  value       = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? azurerm_user_assigned_identity.cert_manager_identity[0].id : null
}

output "cert_manager_identity_principal_id" {
  description = "The principal ID of the cert-manager identity"
  value       = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? azurerm_user_assigned_identity.cert_manager_identity[0].principal_id : null
}

output "cert_manager_identity_client_id" {
  description = "The client ID of the cert-manager identity"
  value       = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? azurerm_user_assigned_identity.cert_manager_identity[0].client_id : null
}

output "karpenter_identity_id" {
  description = "The ID of the karpenter identity"
  value       = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? azurerm_user_assigned_identity.karpenter_identity[0].id : null
}

output "karpenter_identity_principal_id" {
  description = "The principal ID of the karpenter identity"
  value       = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? azurerm_user_assigned_identity.karpenter_identity[0].principal_id : null
}

output "karpenter_identity_client_id" {
  description = "The client ID of the karpenter identity"
  value       = var.create_workload_identities && var.workload_identity_enabled && var.oidc_issuer_enabled ? azurerm_user_assigned_identity.karpenter_identity[0].client_id : null
} 