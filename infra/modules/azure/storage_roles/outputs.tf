output "role_assignment_ids" {
  description = "List of role assignment IDs created for Entra ID authentication"
  value       = var.create ? azurerm_role_assignment.this[*].id : []
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
} 