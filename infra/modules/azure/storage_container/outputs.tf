/**
 * Outputs from the Azure Storage Container module
 * These outputs provide access to container properties for use in other Terraform resources
 * or for reference in operational scripts and documentation.
 */

output "containers" {
  description = "Map of created containers with their properties"
  value       = azurerm_storage_container.containers
  # This provides full access to all container properties including name, access_type, metadata, and resource ID
}

output "container_ids" {
  description = "Map of container names to their resource IDs"
  value = {
    for name, container in azurerm_storage_container.containers : name => container.id
  }
  # Useful for role assignments or other resources that need to reference specific containers
  # Example usage: module.storage_containers.container_ids["mycontainer"]
}

output "container_names" {
  description = "List of created container names"
  value       = [for container in azurerm_storage_container.containers : container.name]
  # Provides a simple list of all container names created by this module
  # Useful for iteration or validation
} 