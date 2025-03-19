/**
 * Outputs for the AKS Cluster module
 *
 * This file contains all outputs from the AKS cluster module, organized by category.
 */

# Cluster Identity
output "principal_id" {
  description = "The principal ID of the system assigned identity of the AKS cluster"
  value       = try(azurerm_kubernetes_cluster.aks_cluster.identity[0].principal_id, "")
}

output "tenant_id" {
  description = "The tenant ID of the system assigned identity of the AKS cluster"
  value       = try(azurerm_kubernetes_cluster.aks_cluster.identity[0].tenant_id, "")
}

# Cluster Information
output "id" {
  description = "The AKS cluster resource ID"
  value       = azurerm_kubernetes_cluster.aks_cluster.id
}

output "name" {
  description = "The name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.name
}

output "location" {
  description = "The location where the AKS cluster is deployed"
  value       = azurerm_kubernetes_cluster.aks_cluster.location
}

output "resource_group_name" {
  description = "The name of the resource group the AKS cluster is deployed in"
  value       = azurerm_kubernetes_cluster.aks_cluster.resource_group_name
}

output "kubernetes_version" {
  description = "The Kubernetes version running on the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.kubernetes_version
}

output "dns_prefix" {
  description = "The DNS prefix of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.dns_prefix
}

output "sku_tier" {
  description = "The SKU tier of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.sku_tier
}

output "private_cluster_enabled" {
  description = "Whether the AKS cluster is private or not"
  value       = azurerm_kubernetes_cluster.aks_cluster.private_cluster_enabled
}

output "private_dns_zone_id" {
  description = "The private DNS zone ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.private_dns_zone_id
}

output "private_fqdn" {
  description = "The private FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.private_fqdn
}

# Node Pool Information
output "default_node_pool_name" {
  description = "The name of the default node pool"
  value       = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].name
}

output "default_node_pool_vm_size" {
  description = "The VM size of the default node pool"
  value       = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].vm_size
}

output "default_node_pool_count" {
  description = "The number of nodes in the default node pool"
  value       = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].node_count
}

output "default_node_pool_min_count" {
  description = "The minimum number of nodes in the default node pool when auto-scaling is enabled"
  value       = try(azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].min_count, null)
}

output "default_node_pool_max_count" {
  description = "The maximum number of nodes in the default node pool when auto-scaling is enabled"
  value       = try(azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].max_count, null)
}

output "default_node_pool_node_labels" {
  description = "The labels applied to the nodes in the default node pool"
  value       = try(azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].node_labels, {})
}

output "default_node_pool_os_disk_size_gb" {
  description = "The OS disk size in GB for the default node pool"
  value       = azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].os_disk_size_gb
}

output "default_node_pool_max_pods" {
  description = "The maximum number of pods per node in the default node pool"
  value       = try(azurerm_kubernetes_cluster.aks_cluster.default_node_pool[0].max_pods, null)
}

# Authentication
output "kube_config_raw" {
  description = "The raw Kubernetes configuration"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config_raw
  sensitive   = true
}

output "kube_admin_config_raw" {
  description = "The raw Kubernetes admin configuration"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_admin_config_raw
  sensitive   = true
}

output "host" {
  description = "The Kubernetes cluster API server endpoint"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].host
  sensitive   = true
}

output "username" {
  description = "The username for the Kubernetes cluster admin"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].username
  sensitive   = true
}

output "password" {
  description = "The password for the Kubernetes cluster admin"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].password
  sensitive   = true
}

output "client_certificate" {
  description = "The client certificate for the Kubernetes cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "The client key for the Kubernetes cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The CA certificate for the Kubernetes cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

# OIDC and Workload Identity
output "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = try(azurerm_kubernetes_cluster.aks_cluster.oidc_issuer_url, "")
}

# Node resource group
output "node_resource_group" {
  description = "The name of the resource group that contains the AKS nodes"
  value       = azurerm_kubernetes_cluster.aks_cluster.node_resource_group
}

# Network Information
output "network_profile" {
  description = "The network profile of the AKS cluster"
  value = {
    network_plugin     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_plugin
    network_policy     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_policy
    load_balancer_sku  = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].load_balancer_sku
    service_cidr       = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].service_cidr
    dns_service_ip     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].dns_service_ip
    pod_cidr          = try(azurerm_kubernetes_cluster.aks_cluster.network_profile[0].pod_cidr, "")
    outbound_type     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].outbound_type
  }
}

output "app_node_pool_id" {
  description = "The ID of the application node pool"
  value       = var.create_app_nodepool ? azurerm_kubernetes_cluster_node_pool.apps[0].id : null
}

output "kubelet_identity" {
  description = "The kubelet managed identity assigned to the AKS cluster"
  value = {
    client_id                 = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].client_id
    object_id                 = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].object_id
    user_assigned_identity_id = azurerm_kubernetes_cluster.aks_cluster.kubelet_identity[0].user_assigned_identity_id
  }
}

output "identity" {
  description = "The identity used by the AKS cluster"
  value = {
    principal_id = azurerm_user_assigned_identity.aks_identity.principal_id
    tenant_id    = azurerm_user_assigned_identity.aks_identity.tenant_id
    client_id    = azurerm_user_assigned_identity.aks_identity.client_id
    id           = azurerm_user_assigned_identity.aks_identity.id
  }
}

output "node_resource_group_id" {
  description = "The ID of the resource group containing the AKS cluster's node resources"
  value       = azurerm_kubernetes_cluster.aks_cluster.node_resource_group_id
}

output "cert_manager_identity" {
  description = "The managed identity for cert-manager, if created"
  value = var.workload_identity_enabled && var.oidc_issuer_enabled ? {
    id           = azurerm_user_assigned_identity.cert_manager_identity[0].id
    client_id    = azurerm_user_assigned_identity.cert_manager_identity[0].client_id
    principal_id = azurerm_user_assigned_identity.cert_manager_identity[0].principal_id
  } : null
}

output "karpenter_identity" {
  description = "The managed identity for Karpenter, if created"
  value = var.workload_identity_enabled && var.oidc_issuer_enabled ? {
    id           = azurerm_user_assigned_identity.karpenter_identity[0].id
    client_id    = azurerm_user_assigned_identity.karpenter_identity[0].client_id
    principal_id = azurerm_user_assigned_identity.karpenter_identity[0].principal_id
  } : null
}

output "fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.fqdn
}

output "network_profile_outbound_type" {
  description = "The outbound type of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].outbound_type
} 