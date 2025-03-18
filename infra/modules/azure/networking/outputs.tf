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