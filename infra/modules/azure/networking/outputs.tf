output "vnet_id" {
  description = "The ID of the virtual network"
  value       = var.create ? azurerm_virtual_network.vnet[0].id : null
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = var.create ? azurerm_virtual_network.vnet[0].name : null
}

output "vnet_resource_group_name" {
  description = "The name of the resource group containing the virtual network"
  value       = var.create ? var.resource_group_name : null
}

output "vnet_location" {
  description = "The location of the virtual network"
  value       = var.create ? azurerm_virtual_network.vnet[0].location : null
}

output "vnet_address_space" {
  description = "The address space of the virtual network"
  value       = var.create ? azurerm_virtual_network.vnet[0].address_space : []
}

output "subnet_ids" {
  description = "Map of subnet names to subnet IDs"
  value       = var.create ? { for k, v in azurerm_subnet.subnet : k => v.id } : {}
}

output "nsg_ids" {
  description = "Map of subnet names to network security group IDs"
  value       = var.create ? { for k, v in azurerm_network_security_group.nsg : k => v.id } : {}
}

# AKS networking outputs
output "aks_subnet_id" {
  description = "The ID of the subnet used for AKS nodes"
  value       = var.create && var.enable_aks_networking && var.aks_subnet_name != null ? azurerm_subnet.subnet[var.aks_subnet_name].id : null
}

output "aks_private_dns_zone_id" {
  description = "The ID of the AKS private DNS zone if created"
  value       = var.create && var.enable_aks_networking && var.aks_private_cluster_enabled && var.aks_private_dns_zone_id == null ? try(azurerm_private_dns_zone.aks[0].id, null) : var.create ? var.aks_private_dns_zone_id : null
}

output "aks_private_dns_zone_name" {
  description = "The name of the AKS private DNS zone if created"
  value       = var.create && var.enable_aks_networking && var.aks_private_cluster_enabled && var.aks_private_dns_zone_id == null ? try(azurerm_private_dns_zone.aks[0].name, null) : null
}

output "aks_nsg_id" {
  description = "The ID of the network security group attached to the AKS subnet"
  value       = var.create && var.enable_aks_networking && var.aks_subnet_name != null ? azurerm_network_security_group.nsg[var.aks_subnet_name].id : null
}

output "vnet_subnet_ids" {
  description = "List of all subnet IDs in the virtual network"
  value       = var.create ? [for subnet in azurerm_subnet.subnet : subnet.id] : []
}

output "private_endpoints_subnet_id" {
  description = "The ID of the private endpoints subnet if it exists"
  value       = var.create && contains(keys(var.subnets), "az1-endpoint-subnet") ? azurerm_subnet.subnet["az1-endpoint-subnet"].id : null
}

# ---------------------------------------------------------------------------
# Cross-cloud interface outputs
# These outputs use cloud-agnostic names so downstream modules (cilium, argocd)
# can consume networking outputs regardless of the underlying cloud provider.
# ---------------------------------------------------------------------------

output "network_id" {
  description = "Cloud-agnostic network identifier (VNet ID on Azure, VPC ID on AWS)"
  value       = var.create ? azurerm_virtual_network.vnet[0].id : null
}

output "network_name" {
  description = "Cloud-agnostic network name"
  value       = var.create ? azurerm_virtual_network.vnet[0].name : null
}

output "kubernetes_subnet_id" {
  description = "Cloud-agnostic subnet ID for Kubernetes nodes"
  value       = var.create && var.enable_aks_networking && var.aks_subnet_name != null ? azurerm_subnet.subnet[var.aks_subnet_name].id : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
