output "vnet_id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.vnet.name
}

output "vnet_resource_group_name" {
  description = "The name of the resource group containing the virtual network"
  value       = var.resource_group_name
}

output "vnet_location" {
  description = "The location of the virtual network"
  value       = azurerm_virtual_network.vnet.location
}

output "vnet_address_space" {
  description = "The address space of the virtual network"
  value       = azurerm_virtual_network.vnet.address_space
}

output "subnet_ids" {
  description = "Map of subnet names to subnet IDs"
  value       = { for k, v in azurerm_subnet.subnet : k => v.id }
}

output "nsg_ids" {
  description = "Map of subnet names to network security group IDs"
  value       = { for k, v in azurerm_network_security_group.nsg : k => v.id }
}

# AKS networking outputs
output "aks_subnet_id" {
  description = "The ID of the subnet used for AKS nodes"
  value       = var.enable_aks_networking && var.aks_subnet_name != null ? azurerm_subnet.subnet[var.aks_subnet_name].id : null
}

output "aks_private_dns_zone_id" {
  description = "The ID of the AKS private DNS zone if created"
  value       = var.enable_aks_networking && var.aks_private_cluster_enabled && var.aks_private_dns_zone_id == null ? try(azurerm_private_dns_zone.aks[0].id, null) : var.aks_private_dns_zone_id
}

output "aks_private_dns_zone_name" {
  description = "The name of the AKS private DNS zone if created"
  value       = var.enable_aks_networking && var.aks_private_cluster_enabled && var.aks_private_dns_zone_id == null ? try(azurerm_private_dns_zone.aks[0].name, null) : null
}

output "aks_nsg_id" {
  description = "The ID of the network security group attached to the AKS subnet"
  value       = var.enable_aks_networking && var.aks_subnet_name != null ? azurerm_network_security_group.nsg[var.aks_subnet_name].id : null
}

output "vnet_subnet_ids" {
  description = "List of all subnet IDs in the virtual network"
  value       = [for subnet in azurerm_subnet.subnet : subnet.id]
}

output "private_endpoints_subnet_id" {
  description = "The ID of the private endpoints subnet if it exists"
  value       = contains(keys(var.subnets), "az1-endpoint-subnet") ? azurerm_subnet.subnet["az1-endpoint-subnet"].id : null
} 