/**
 * Outputs for the AKS Cluster Composite module
 */

# Core cluster outputs
output "id" {
  description = "The ID of the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].id : null
}

output "name" {
  description = "The name of the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].name : null
}

output "resource_group_name" {
  description = "The name of the resource group that contains the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].resource_group_name : null
}

output "location" {
  description = "The location/region of the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].location : null
}

output "kubernetes_version" {
  description = "The version of Kubernetes running on the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].kubernetes_version : null
}

output "kube_config_raw" {
  description = "The raw Kubernetes config to be used with kubectl and other tools"
  value       = var.create_resources ? module.aks_core[0].kube_config_raw : null
  sensitive   = true
}

output "kube_admin_config_raw" {
  description = "The raw Kubernetes admin config to be used with kubectl and other tools"
  value       = var.create_resources ? module.aks_core[0].kube_admin_config_raw : null
  sensitive   = true
}

output "host" {
  description = "The Kubernetes cluster server host"
  value       = var.create_resources ? module.aks_core[0].host : null
  sensitive   = true
}

output "client_certificate" {
  description = "The client certificate for authentication"
  value       = var.create_resources ? module.aks_core[0].client_certificate : null
  sensitive   = true
}

output "client_key" {
  description = "The client key for authentication"
  value       = var.create_resources ? module.aks_core[0].client_key : null
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The cluster CA certificate for communication with the cluster"
  value       = var.create_resources ? module.aks_core[0].cluster_ca_certificate : null
  sensitive   = true
}

# Node pool outputs
output "default_node_pool_name" {
  description = "The name of the default node pool"
  value       = var.create_resources ? module.aks_core[0].default_node_pool_name : null
}

output "app_node_pool_id" {
  description = "The ID of the application node pool"
  value       = var.create_resources && var.app_node_pool_enabled ? module.aks_node_pools[0].app_node_pool_id : null
}

output "app_node_pool_name" {
  description = "The name of the application node pool"
  value       = var.create_resources && var.app_node_pool_enabled ? module.aks_node_pools[0].app_node_pool_name : null
}

# Identity and security outputs
output "node_resource_group" {
  description = "The name of the resource group containing the AKS cluster's node resources"
  value       = var.create_resources ? module.aks_core[0].node_resource_group : null
}

output "node_resource_group_id" {
  description = "The ID of the resource group containing the AKS cluster's node resources"
  value       = var.create_resources ? module.aks_core[0].node_resource_group_id : null
}

output "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].oidc_issuer_url : null
}

output "kubelet_identity" {
  description = "The kubelet managed identity assigned to the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].kubelet_identity : null
}

output "identity" {
  description = "The identity of the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].identity : null
}

output "fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = var.create_resources ? module.aks_core[0].fqdn : null
}

# Identity module outputs
output "aks_identity_id" {
  description = "The ID of the user-assigned managed identity for the AKS cluster"
  value       = var.create_resources ? module.identities[0].aks_identity_id : null
}

output "aks_identity_client_id" {
  description = "The client ID of the user-assigned managed identity for the AKS cluster"
  value       = var.create_resources ? module.identities[0].aks_identity_client_id : null
}

output "aks_identity_principal_id" {
  description = "The principal ID of the user-assigned managed identity for the AKS cluster"
  value       = var.create_resources ? module.identities[0].aks_identity_principal_id : null
}

# Workload identity outputs
output "cert_manager_identity" {
  description = "The cert-manager identity if created"
  value       = var.create_resources && var.workload_identity_enabled && var.oidc_issuer_enabled ? module.workload_identity_setup[0].cert_manager_identity : null
}

output "karpenter_identity" {
  description = "The Karpenter identity if created"
  value       = var.create_resources && var.workload_identity_enabled && var.oidc_issuer_enabled ? module.workload_identity_setup[0].karpenter_identity : null
}

output "workload_identities" {
  description = "Map of all workload identities created by the module"
  value       = var.create_resources && var.workload_identity_enabled && var.oidc_issuer_enabled ? module.workload_identity_setup[0].workload_identities : {}
}

# Networking module outputs
output "network_plugin_mode" {
  description = "The network plugin mode used by the AKS cluster"
  value       = var.create_resources ? module.aks_networking[0].network_plugin_mode : null
}

output "network_plugin" {
  description = "The network plugin used by the AKS cluster"
  value       = var.create_resources ? module.aks_networking[0].network_plugin : null
}

output "network_policy" {
  description = "The network policy used by the AKS cluster"
  value       = var.create_resources ? module.aks_networking[0].network_policy : null
}

output "pod_cidr" {
  description = "The CIDR block used for pod IP addresses"
  value       = var.create_resources ? module.aks_networking[0].pod_cidr : null
}

output "service_cidr" {
  description = "The CIDR block used for service IP addresses"
  value       = var.create_resources ? module.aks_networking[0].service_cidr : null
}

output "private_cluster_enabled" {
  description = "Whether the AKS cluster is a private cluster"
  value       = var.create_resources ? module.aks_networking[0].private_cluster_enabled : null
} 