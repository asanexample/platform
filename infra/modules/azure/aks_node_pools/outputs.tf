/**
 * Outputs for the AKS Node Pools module
 */

output "app_node_pool_id" {
  description = "The ID of the application node pool"
  value       = var.create && var.app_node_pool_enabled ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].id : null
}

output "app_node_pool_name" {
  description = "The name of the application node pool"
  value       = var.create && var.app_node_pool_enabled ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].name : null
}

output "app_node_pool_node_count" {
  description = "The number of nodes in the application node pool"
  value       = var.create && var.app_node_pool_enabled ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].node_count : null
}

output "app_node_pool_vm_size" {
  description = "The VM size of the application node pool"
  value       = var.create && var.app_node_pool_enabled ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].vm_size : null
}

output "app_node_pool_os_disk_size_gb" {
  description = "The OS disk size of the application node pool"
  value       = var.create && var.app_node_pool_enabled ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].os_disk_size_gb : null
}

output "app_node_pool_auto_scaling_enabled" {
  description = "Whether auto-scaling is enabled for the application node pool"
  value       = var.create && var.app_node_pool_enabled ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].auto_scaling_enabled : null
}

output "app_node_pool_min_count" {
  description = "The minimum number of nodes in the application node pool"
  value       = var.create && var.app_node_pool_enabled && var.app_node_pool_enable_auto_scaling ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].min_count : null
}

output "app_node_pool_max_count" {
  description = "The maximum number of nodes in the application node pool"
  value       = var.create && var.app_node_pool_enabled && var.app_node_pool_enable_auto_scaling ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].max_count : null
}

output "app_node_pool_mode" {
  description = "The mode of the application node pool"
  value       = var.create && var.app_node_pool_enabled ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].mode : null
}

output "app_node_pool_node_labels" {
  description = "The node labels of the application node pool"
  value       = var.create && var.app_node_pool_enabled ? azurerm_kubernetes_cluster_node_pool.app_node_pool[0].node_labels : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
