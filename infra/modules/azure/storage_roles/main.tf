/**
 * # Azure Storage Role Assignments Module
 *
 * This module creates role assignments for Azure Storage to enable Entra ID authentication.
 * It's intended to be used as a separate module when transitioning from access keys to Entra ID.
 */

# Role assignments for Entra ID authentication
# This creates RBAC role assignments for principals to access the storage account
resource "azurerm_role_assignment" "this" {
  count                = length(var.role_assignments)
  principal_id         = var.role_assignments[count.index].principal_id
  role_definition_name = var.role_assignments[count.index].role_definition_name
  role_definition_id   = var.role_assignments[count.index].role_definition_id
  scope                = var.role_assignments[count.index].scope != null ? var.role_assignments[count.index].scope : var.storage_account_id
  description          = var.role_assignments[count.index].description

  # Note: The prevent_destroy lifecycle rule was removed to allow terraform destroy to work properly.
  # When reinstating this module in production, consider adding the lifecycle block back
  # to prevent accidental deletion of important role assignments.
  # 
  # lifecycle {
  #   prevent_destroy = true
  # }
} 