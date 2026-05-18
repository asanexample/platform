/**
 * Outputs from the Azure Storage Container module
 * These outputs provide access to container properties for use in other Terraform resources
 * or for reference in operational scripts and documentation.
 */

output "containers" {
  description = "Map of created containers with their properties"
  value       = var.create ? azurerm_storage_container.containers : {}
  # This provides full access to all container properties including name, access_type, metadata, and resource ID
}

output "container_ids" {
  description = "Map of container names to their resource IDs"
  value = var.create ? {
    for name, container in azurerm_storage_container.containers : name => container.id
  } : {}
  # Useful for role assignments or other resources that need to reference specific containers
  # Example usage: module.storage_containers.container_ids["mycontainer"]
}

output "container_names" {
  description = "List of created container names"
  value       = var.create ? [for container in azurerm_storage_container.containers : container.name] : []
  # Provides a simple list of all container names created by this module
  # Useful for iteration or validation
}

output "container_resource_manager_ids" {
  description = "Map of container names to their resource manager IDs for use with role assignments"
  value = var.create ? {
    for name, container in azurerm_storage_container.containers : name => container.resource_manager_id
  } : {}
  # Useful for role assignments using the resource manager ID
  # Different from the standard ID which is used for general references
}

output "role_assignments" {
  description = "Map of role assignments created for containers"
  value       = var.create ? azurerm_role_assignment.container_role_assignments : {}
  # Provides access to all role assignment properties for each container
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
} 