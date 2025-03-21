variable "storage_account_id" {
  description = "ID of the storage account to assign roles for"
  type        = string
}

variable "role_assignments" {
  description = "List of role assignments to create for Entra ID authentication. Should contain principal_id, role_definition_name or role_definition_id, and scope (optional)."
  type = list(object({
    principal_id         = string
    role_definition_name = optional(string, null)
    role_definition_id   = optional(string, null)
    description          = optional(string, null)
    scope                = optional(string, null) # Defaults to storage account resource ID
  }))
  default = []

  validation {
    condition = alltrue([
      for ra in var.role_assignments : ra.role_definition_name != null || ra.role_definition_id != null
    ])
    error_message = "Either role_definition_name or role_definition_id must be provided for each role assignment."
  }
} 