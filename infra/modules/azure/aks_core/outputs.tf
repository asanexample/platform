/**
 * Outputs for the AKS Core module
 */

output "id" {
  description = "The ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.id
}

output "name" {
  description = "The name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.name
}

output "resource_group_name" {
  description = "The name of the resource group that contains the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.resource_group_name
}

output "location" {
  description = "The location/region of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.location
}

output "kubernetes_version" {
  description = "The version of Kubernetes running on the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.kubernetes_version
}

output "kube_config_raw" {
  description = "The raw Kubernetes config to be used with kubectl and other tools"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config_raw
  sensitive   = true
}

output "kube_admin_config_raw" {
  description = "The raw Kubernetes admin config to be used with kubectl and other tools"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_admin_config_raw
  sensitive   = true
}

output "host" {
  description = "The Kubernetes cluster server host"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].host
  sensitive   = true
}

output "client_certificate" {
  description = "The client certificate for authentication"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "The client key for authentication"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The cluster CA certificate for communication with the cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "default_node_pool_name" {
  description = "The name of the default node pool"
  value       = try(azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].name, null)
}

output "node_resource_group" {
  description = "The name of the resource group containing the AKS cluster's node resources"
  value       = azurerm_kubernetes_cluster.aks_cluster.node_resource_group
}

output "node_resource_group_id" {
  description = "The ID of the resource group containing the AKS cluster's node resources"
  value       = azurerm_kubernetes_cluster.aks_cluster.node_resource_group_id
}

output "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url
}

output "kubelet_identity" {
  description = "The kubelet managed identity assigned to the AKS cluster"
  value = try(
    {
      client_id                 = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].client_id
      object_id                 = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].object_id
      user_assigned_identity_id = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].user_assigned_identity_id
    },
    null
  )
}

output "identity" {
  description = "The identity of the AKS cluster"
  value = var.identity_type == "SystemAssigned" ? {
    principal_id = azurerm_kubernetes_cluster.aks_cluster.identity[0].principal_id
    tenant_id    = azurerm_kubernetes_cluster.aks_cluster.identity[0].tenant_id
  } : null
}

output "fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.fqdn
} 