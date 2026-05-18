/**
 * # Azure Storage Container Module
 *
 * This module creates one or more containers in an existing Azure Storage Account.
 * It's designed for decoupling container management from storage account creation,
 * allowing for:
 * - Independent lifecycle management of containers
 * - Granular permission control per container
 * - Flexibility to add containers to existing storage accounts
 * - Separate teams to manage containers without storage account access
 */

# Create multiple storage containers based on the input map
# Each container has its own settings for access type and metadata
resource "azurerm_storage_container" "containers" {
  # Iterate through each container definition in the input map
  for_each = var.create ? var.containers : {}

  # Container name - must follow Azure naming rules
  # (3-63 chars, lowercase alphanumeric and dashes)
  name = each.value.name

  # Reference to parent storage account by ID
  # This is the required parameter format for Azure provider 4.x+
  storage_account_id = var.storage_account_id

  # Access level for the container:
  # - private: No anonymous access (default)
  # - blob: Anonymous read access for blobs only
  # - container: Anonymous read access for container and blobs
  container_access_type = each.value.container_access_type

  # Custom metadata key-value pairs for the container
  # These can be used for organization, categorization, or application needs
  metadata = each.value.metadata
}

# Create role assignments for container-level access
# This enables Entra ID (Azure AD) authentication for containers
resource "azurerm_role_assignment" "container_role_assignments" {
  for_each = var.create ? {
    for idx, ra in var.role_assignments : "${ra.container_key}-${ra.principal_id}-${ra.role_definition_name}" => ra
  } : {}

  # Set the scope to the specific container
  scope = azurerm_storage_container.containers[each.value.container_key].resource_manager_id

  # Principal ID (user, group, service principal)
  principal_id = each.value.principal_id

  # Role definition name or ID
  role_definition_name = each.value.role_definition_name

  # Optional properties
  description                      = each.value.description
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  principal_type                   = each.value.principal_type
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
} 