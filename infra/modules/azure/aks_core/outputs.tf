/**
 * Outputs for the AKS Core module
 */

output "id" {
  description = "The ID of the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].id : null
}

output "name" {
  description = "The name of the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].name : null
}

output "resource_group_name" {
  description = "The name of the resource group that contains the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].resource_group_name : null
}

output "location" {
  description = "The location/region of the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].location : null
}

output "kubernetes_version" {
  description = "The version of Kubernetes running on the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].kubernetes_version : null
}

output "kube_config_raw" {
  description = "The raw Kubernetes config to be used with kubectl and other tools"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].kube_config_raw : null
  sensitive   = true
}

output "kube_admin_config_raw" {
  description = "The raw Kubernetes admin config to be used with kubectl and other tools"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].kube_admin_config_raw : null
  sensitive   = true
}

output "host" {
  description = "The Kubernetes cluster server host"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].kube_config[0].host : null
  sensitive   = true
}

output "client_certificate" {
  description = "The client certificate for authentication"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].kube_config[0].client_certificate : null
  sensitive   = true
}

output "client_key" {
  description = "The client key for authentication"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].kube_config[0].client_key : null
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The cluster CA certificate for communication with the cluster"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].kube_config[0].cluster_ca_certificate : null
  sensitive   = true
}

output "default_node_pool_name" {
  description = "The name of the default node pool"
  value       = var.create ? try(azurerm_kubernetes_cluster.aks_cluster[0].default_node_pool[0].name, null) : null
}

output "node_resource_group" {
  description = "The name of the resource group containing the AKS cluster's node resources"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].node_resource_group : null
}

output "node_resource_group_id" {
  description = "The ID of the resource group containing the AKS cluster's node resources"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].node_resource_group_id : null
}

output "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].oidc_issuer_url : null
}

output "kubelet_identity" {
  description = "The kubelet managed identity assigned to the AKS cluster"
  value = var.create ? try(
    {
      client_id                 = azurerm_kubernetes_cluster.aks_cluster[0].kubelet_identity[0].client_id
      object_id                 = azurerm_kubernetes_cluster.aks_cluster[0].kubelet_identity[0].object_id
      user_assigned_identity_id = azurerm_kubernetes_cluster.aks_cluster[0].kubelet_identity[0].user_assigned_identity_id
    },
    null
  ) : null
}

output "identity" {
  description = "The identity of the AKS cluster"
  value = var.create && var.identity_type == "SystemAssigned" ? {
    principal_id = azurerm_kubernetes_cluster.aks_cluster[0].identity[0].principal_id
    tenant_id    = azurerm_kubernetes_cluster.aks_cluster[0].identity[0].tenant_id
  } : null
}

output "fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.aks_cluster[0].fqdn : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
