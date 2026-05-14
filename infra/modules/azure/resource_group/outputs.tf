/**
 * # Azure Resource Group Module - Outputs
 *
 * Output values for the resource group module.
 */

output "name" {
  description = "The name of the resource group"
  value       = var.create ? azurerm_resource_group.rg[0].name : null
}

output "id" {
  description = "The ID of the resource group"
  value       = var.create ? azurerm_resource_group.rg[0].id : null
}

output "location" {
  description = "The location of the resource group"
  value       = var.create ? azurerm_resource_group.rg[0].location : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
} 