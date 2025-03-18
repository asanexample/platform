/**
 * This module allows the management of containers within an Azure Storage Account. 
 * It supports creating multiple containers with different access types and metadata.
 * It's designed to decouple container management from storage account lifecycle.
 */

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