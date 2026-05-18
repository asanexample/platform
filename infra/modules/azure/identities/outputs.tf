/**
 * # Outputs for the Azure Identities Module
 *
 * This file defines all outputs for the Azure Identities module.
 */

# -----------------------------------------------------------------------------
# AKS CLUSTER IDENTITY OUTPUTS
# -----------------------------------------------------------------------------

output "aks_identity_id" {
  description = "ID of the user-assigned managed identity for the AKS cluster."
  value       = var.create && var.create_aks_identity ? azurerm_user_assigned_identity.aks_identity[0].id : null
}

output "aks_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity for the AKS cluster."
  value       = var.create && var.create_aks_identity ? azurerm_user_assigned_identity.aks_identity[0].principal_id : null
}

output "aks_identity_client_id" {
  description = "Client ID of the user-assigned managed identity for the AKS cluster."
  value       = var.create && var.create_aks_identity ? azurerm_user_assigned_identity.aks_identity[0].client_id : null
}

# -----------------------------------------------------------------------------
# WORKLOAD IDENTITY OUTPUTS
# -----------------------------------------------------------------------------

output "workload_identities" {
  description = "Map of all workload identities created by the module."
  value = var.create ? {
    for name, identity in azurerm_user_assigned_identity.workload_identities : name => {
      id           = identity.id
      name         = identity.name
      principal_id = identity.principal_id
      client_id    = identity.client_id
    }
  } : {}
}

output "cert_manager_identity" {
  description = "Details of the cert-manager identity if created."
  value = var.create && contains(keys(azurerm_user_assigned_identity.workload_identities), "cert-manager") ? {
    id           = azurerm_user_assigned_identity.workload_identities["cert-manager"].id
    client_id    = azurerm_user_assigned_identity.workload_identities["cert-manager"].client_id
    principal_id = azurerm_user_assigned_identity.workload_identities["cert-manager"].principal_id
  } : null
}

output "karpenter_identity" {
  description = "Details of the Karpenter identity if created."
  value = var.create && contains(keys(azurerm_user_assigned_identity.workload_identities), "karpenter") ? {
    id           = azurerm_user_assigned_identity.workload_identities["karpenter"].id
    client_id    = azurerm_user_assigned_identity.workload_identities["karpenter"].client_id
    principal_id = azurerm_user_assigned_identity.workload_identities["karpenter"].principal_id
  } : null
}

output "federated_identity_credentials" {
  description = "Map of all federated identity credentials created by the module."
  value = var.create ? {
    for key, credential in azurerm_federated_identity_credential.workload_credentials : key => {
      id       = credential.id
      name     = credential.name
      subject  = credential.subject
      issuer   = credential.issuer
      audience = credential.audience
    }
  } : {}
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
