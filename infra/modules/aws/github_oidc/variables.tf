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
    Map of IAM role name to its GitHub Actions OIDC configuration. A role is scoped by
    EITHER the OIDC `sub` claim (repos × branches/events — the common case) OR the
    `job_workflow_ref` claim (for a role assumed only while a specific REUSABLE workflow
    runs, regardless of caller — the `sub` then reflects the caller, so `job_workflow_ref`
    is the correct scope). Set `repos` for the `sub` form, `job_workflow_refs` for the
    reusable-workflow form, or both. Each role carries the given managed/inline policies.
  EOT
  type = map(object({
    repos    = optional(list(string), [])
    branches = optional(list(string), ["main"])
    events   = optional(list(string), [])
    # Reusable-workflow refs (without the org prefix), e.g.
    # "trusted-ci/.github/workflows/slsa-provenance.yml@*". The org is prepended from
    # var.github_org. When set, the trust policy adds a StringLike `job_workflow_ref`
    # condition; when empty, only the `sub` condition (if any repos) applies.
    job_workflow_refs    = optional(list(string), [])
    role_policy_arns     = optional(list(string), [])
    inline_policy        = optional(string)
    max_session_duration = optional(number, 3600)
    tags                 = optional(map(string), {}) # merged onto var.tags (e.g. { Team = "alpha" })
  }))
  default = {}

  # Guard against an over-broad trust policy: a role with neither repos nor
  # job_workflow_refs would condition only on `aud`, trusting EVERY GitHub Actions OIDC
  # subject. Require at least one scope.
  validation {
    condition = alltrue([
      for _, role in var.roles : length(role.repos) > 0 || length(role.job_workflow_refs) > 0
    ])
    error_message = "Each role must set at least one of `repos` (sub scope) or `job_workflow_refs` (reusable-workflow scope); a role with neither would trust any GitHub OIDC subject."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
