/**
 * This module allows the management of containers within an Azure Storage Account.
 * It supports creating multiple containers with different access types and metadata.
 * It's designed to decouple container management from storage account lifecycle.
 */

variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "storage_account_id" {
  description = "ID of the Azure Storage Account where containers will be created"
  type        = string
  # Example: "/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Storage/storageAccounts/{storage-account-name}"
}

variable "containers" {
  description = "Map of containers to create in the storage account"
  type = map(object({
    # Name of the container - must follow Azure naming rules
    name = string
    # Access type: "private" (default), "blob" (anonymous blob read), or "container" (anonymous container read)
    container_access_type = optional(string, "private")
    # Optional metadata as key-value pairs to add to the container
    metadata = optional(map(string), {})
  }))

  # Validate container names according to Azure Storage requirements:
  # - 3-63 characters long
  # - Start and end with letter or number
  # - Contain only lowercase letters, numbers, and dashes
  validation {
    condition = alltrue([
      for k, v in var.containers : can(regex("^[a-z0-9][-a-z0-9]{1,61}[a-z0-9]$", v.name))
    ])
    error_message = "Container names must be 3-63 characters long, start and end with a letter or number, and can contain only lowercase letters, numbers, and dashes."
  }

  # Ensure the container_access_type is one of the allowed values
  validation {
    condition = alltrue([
      for k, v in var.containers : contains(["blob", "container", "private"], v.container_access_type)
    ])
    error_message = "Container access type must be one of: blob, container, private."
  }
}

variable "role_assignments" {
  description = "List of role assignments to create for containers"
  type = list(object({
    # Container key from var.containers to assign the role to
    container_key = string
    # Principal ID to give the role to (user, group, service principal, etc.)
    principal_id = string
    # The name of the role to assign (e.g., "Storage Blob Data Contributor")
    role_definition_name = string
    # Optional description for the role assignment
    description = optional(string, null)
    # Optional condition for the role assignment
    condition = optional(string, null)
    # Optional condition version for the role assignment
    condition_version = optional(string, null)
    # Optional principal type (ServicePrincipal, User, Group)
    principal_type = optional(string, null)
    # Optional skip service principal AAD check
    skip_service_principal_aad_check = optional(bool, false)
  }))
  default = []

  validation {
    condition = alltrue([
      for ra in var.role_assignments : contains(keys(var.containers), ra.container_key)
    ])
    error_message = "Each role_assignment must reference a valid container_key from the containers variable."
  }
} 