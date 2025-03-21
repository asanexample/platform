output "role_assignment_ids" {
  description = "List of role assignment IDs created for Entra ID authentication"
  value       = azurerm_role_assignment.this[*].id
} 