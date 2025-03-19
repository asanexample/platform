/**
 * Outputs for the AKS Cluster module
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

output "default_node_pool_id" {
  description = "The ID of the default node pool"
  value       = azurerm_kubernetes_cluster.aks_cluster.default_node_pool.0.id
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

output "cert_manager_identity" {
  description = "The managed identity for cert-manager, if created"
  value = var.workload_identity_enabled && var.oidc_issuer_enabled ? {
    id         = azurerm_user_assigned_identity.cert_manager_identity[0].id
    client_id  = azurerm_user_assigned_identity.cert_manager_identity[0].client_id
    principal_id = azurerm_user_assigned_identity.cert_manager_identity[0].principal_id
  } : null
}

output "karpenter_identity" {
  description = "The managed identity for Karpenter, if created"
  value = var.workload_identity_enabled && var.oidc_issuer_enabled ? {
    id         = azurerm_user_assigned_identity.karpenter_identity[0].id
    client_id  = azurerm_user_assigned_identity.karpenter_identity[0].client_id
    principal_id = azurerm_user_assigned_identity.karpenter_identity[0].principal_id
  } : null
}

output "aks_dcr_id" {
  description = "The ID of the data collection rule for AKS Prometheus metrics"
  value       = azurerm_monitor_data_collection_rule.aks_dcr.id
}

output "container_insights_dcr_id" {
  description = "The ID of the data collection rule for Container Insights"
  value       = azurerm_monitor_data_collection_rule.container_insights_dcr.id
}

output "fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.fqdn
}

output "private_fqdn" {
  description = "The private FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.private_fqdn
}

output "network_profile" {
  description = "The network profile of the AKS cluster"
  value = {
    network_plugin     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_plugin
    network_policy     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].network_policy
    pod_cidr           = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].pod_cidr
    service_cidr       = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].service_cidr
    dns_service_ip     = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].dns_service_ip
    docker_bridge_cidr = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].docker_bridge_cidr
    outbound_type      = azurerm_kubernetes_cluster.aks_cluster.network_profile[0].outbound_type
  }
} 