/**
 * Outputs for the AKS Networking module
 */

output "network_plugin" {
  description = "The network plugin used"
  value       = var.network_plugin
}

output "network_plugin_mode" {
  description = "The network plugin mode used"
  value       = var.network_plugin_mode
}

output "network_policy" {
  description = "The network policy used"
  value       = var.network_policy
}

output "network_data_plane" {
  description = "The network data plane used"
  value       = var.network_data_plane
}

output "pod_cidr" {
  description = "The CIDR for pod IPs"
  value       = var.pod_cidr
}

output "service_cidr" {
  description = "The CIDR for Kubernetes services"
  value       = var.service_cidr
}

output "dns_service_ip" {
  description = "The IP address for the DNS service"
  value       = var.dns_service_ip
}

output "docker_bridge_cidr" {
  description = "The CIDR for the Docker bridge network"
  value       = var.docker_bridge_cidr
}

output "subnet_id" {
  description = "The ID of the subnet where the AKS cluster is deployed"
  value       = var.subnet_id
}

output "private_cluster_enabled" {
  description = "Whether the AKS cluster is a private cluster"
  value       = var.private_cluster_enabled
}

output "private_dns_zone_id" {
  description = "The ID of the private DNS zone for AKS"
  value       = var.private_cluster_enabled && var.private_dns_zone_id == null ? (length(azurerm_private_dns_zone.aks) > 0 ? azurerm_private_dns_zone.aks[0].id : null) : var.private_dns_zone_id
}

output "private_cluster_public_fqdn_enabled" {
  description = "Whether public FQDN is enabled for private clusters"
  value       = var.private_cluster_public_fqdn_enabled
}

output "nsg_id" {
  description = "The ID of the network security group created for AKS"
  value       = var.subnet_id != null && var.private_cluster_enabled ? (length(azurerm_network_security_group.aks) > 0 ? azurerm_network_security_group.aks[0].id : null) : null
}

output "route_table_id" {
  description = "The ID of the route table for AKS"
  value       = var.subnet_id != null ? (length(data.azurerm_route_table.aks) > 0 ? data.azurerm_route_table.aks[0].id : null) : null
} 