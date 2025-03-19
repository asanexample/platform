/**
 * Outputs for the AKS Cluster Composite module
 */

# Core cluster outputs
output "id" {
  description = "The ID of the AKS cluster"
  value       = module.aks_core.id
}

output "name" {
  description = "The name of the AKS cluster"
  value       = module.aks_core.name
}

output "resource_group_name" {
  description = "The name of the resource group that contains the AKS cluster"
  value       = module.aks_core.resource_group_name
}

output "location" {
  description = "The location/region of the AKS cluster"
  value       = module.aks_core.location
}

output "kubernetes_version" {
  description = "The version of Kubernetes running on the AKS cluster"
  value       = module.aks_core.kubernetes_version
}

output "kube_config_raw" {
  description = "The raw Kubernetes config to be used with kubectl and other tools"
  value       = module.aks_core.kube_config_raw
  sensitive   = true
}

output "kube_admin_config_raw" {
  description = "The raw Kubernetes admin config to be used with kubectl and other tools"
  value       = module.aks_core.kube_admin_config_raw
  sensitive   = true
}

output "host" {
  description = "The Kubernetes cluster server host"
  value       = module.aks_core.host
  sensitive   = true
}

output "client_certificate" {
  description = "The client certificate for authentication"
  value       = module.aks_core.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "The client key for authentication"
  value       = module.aks_core.client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The cluster CA certificate for communication with the cluster"
  value       = module.aks_core.cluster_ca_certificate
  sensitive   = true
}

# Node pool outputs
output "default_node_pool_name" {
  description = "The name of the default node pool"
  value       = module.aks_core.default_node_pool_name
}

output "app_node_pool_id" {
  description = "The ID of the application node pool"
  value       = var.app_node_pool_enabled ? module.aks_node_pools[0].app_node_pool_id : null
}

output "app_node_pool_name" {
  description = "The name of the application node pool"
  value       = var.app_node_pool_enabled ? module.aks_node_pools[0].app_node_pool_name : null
}

# Identity and security outputs
output "node_resource_group" {
  description = "The name of the resource group containing the AKS cluster's node resources"
  value       = module.aks_core.node_resource_group
}

output "node_resource_group_id" {
  description = "The ID of the resource group containing the AKS cluster's node resources"
  value       = module.aks_core.node_resource_group_id
}

output "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = module.aks_core.oidc_issuer_url
}

output "kubelet_identity" {
  description = "The kubelet managed identity assigned to the AKS cluster"
  value       = module.aks_core.kubelet_identity
}

output "identity" {
  description = "The identity of the AKS cluster"
  value       = module.aks_core.identity
}

output "fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = module.aks_core.fqdn
}

# Identity module outputs
output "aks_identity_id" {
  description = "The ID of the user-assigned managed identity for the AKS cluster"
  value       = module.aks_identity.aks_identity_id
}

output "aks_identity_client_id" {
  description = "The client ID of the user-assigned managed identity for the AKS cluster"
  value       = module.aks_identity.aks_identity_client_id
}

output "aks_identity_principal_id" {
  description = "The principal ID of the user-assigned managed identity for the AKS cluster"
  value       = module.aks_identity.aks_identity_principal_id
}

output "cert_manager_identity_id" {
  description = "The ID of the user-assigned managed identity for cert-manager"
  value       = module.aks_identity_update.cert_manager_identity_id
}

output "karpenter_identity_id" {
  description = "The ID of the user-assigned managed identity for Karpenter"
  value       = module.aks_identity_update.karpenter_identity_id
}

# Networking module outputs
output "network_plugin_mode" {
  description = "The network plugin mode used by the AKS cluster"
  value       = module.aks_networking.network_plugin_mode
}

output "network_plugin" {
  description = "The network plugin used by the AKS cluster"
  value       = module.aks_networking.network_plugin
}

output "network_policy" {
  description = "The network policy used by the AKS cluster"
  value       = module.aks_networking.network_policy
}

output "pod_cidr" {
  description = "The CIDR block used for pod IP addresses"
  value       = module.aks_networking.pod_cidr
}

output "service_cidr" {
  description = "The CIDR block used for service IP addresses"
  value       = module.aks_networking.service_cidr
}

output "private_cluster_enabled" {
  description = "Whether the AKS cluster is a private cluster"
  value       = module.aks_networking.private_cluster_enabled
}

# Monitoring outputs
output "diagnostic_setting_id" {
  description = "The ID of the diagnostic setting for the AKS cluster"
  value       = module.aks_monitoring.diagnostic_setting_id
} 