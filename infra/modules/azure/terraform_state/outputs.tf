/**
 * Azure Terraform State Storage Module - Outputs
 *
 * These outputs provide access to the created Azure Storage Account resources,
 * allowing them to be referenced in backend configurations and other resources.
 * Sensitive outputs like access keys are marked as such to protect credentials.
 */

output "storage_account_id" {
  description = "ID of the created storage account"
  value       = module.storage_account.id
  # Full Azure resource ID, useful for RBAC assignments and resource references
  # Format: /subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Storage/storageAccounts/{accountName}
}

output "storage_account_name" {
  description = "Name of the created storage account"
  value       = module.storage_account.name
  # Use this in Terraform backend configuration for the storage_account_name parameter
}

output "primary_access_key" {
  description = "Primary access key for the storage account"
  value       = module.storage_account.primary_access_key
  sensitive   = true
  # SECURITY NOTE: Handle with care - store in key vault or use managed identities instead when possible
  # Used in backend configuration for the access_key parameter
}

output "primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = module.storage_account.primary_connection_string
  sensitive   = true
  # SECURITY NOTE: Contains account name and key - treat as sensitive
  # Useful for applications that need to access the storage account
}

output "tfstate_container_name" {
  description = "Name of the Terraform state container"
  value       = local.tfstate_container_name
  # Use this in Terraform backend configuration for the container_name parameter
  # Default is "tfstate" unless overridden
}

output "tfstate_container_id" {
  description = "Resource ID of the Terraform state container"
  value       = module.storage_account.containers[local.tfstate_container_name].id
  # Full resource ID for the container, useful for RBAC assignments and permission management
  # Format: {storage_account_id}/blobServices/default/containers/{container_name}
}

output "private_endpoint_id" {
  description = "ID of the private endpoint if created"
  value       = length(module.storage_account.private_endpoint_ids) > 0 ? module.storage_account.private_endpoint_ids[0] : null
  # Returns the ID of the private endpoint if one was created, otherwise null
  # Useful for network documentation and dependency management
} 