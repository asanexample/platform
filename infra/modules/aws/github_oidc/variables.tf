variable "create" {
  description = "Whether to create the OIDC provider and roles"
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "roles" {
  description = <<-EOT
    Map of IAM role name to its GitHub Actions OIDC configuration. Each role trusts
    only the listed repos (scoped via the OIDC `sub` claim) for the given branches
    and events, and carries the given managed/inline policies.
  EOT
  type = map(object({
    repos                = list(string)
    branches             = optional(list(string), ["main"])
    events               = optional(list(string), [])
    role_policy_arns     = optional(list(string), [])
    inline_policy        = optional(string)
    max_session_duration = optional(number, 3600)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
