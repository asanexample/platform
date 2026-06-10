variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "roles" {
  description = "Map of IAM roles to create"
  type = map(object({
    description          = optional(string, "")
    path                 = optional(string, "/")
    max_session_duration = optional(number, 3600)
    # Map of principal type -> identifiers. Keys: "aws" (AWS account/role ARNs), "service" (AWS service
    # principals, e.g. "pods.eks.amazonaws.com" for EKS Pod Identity), "federated".
    trust_principals = map(list(string))
    # Trust-policy actions. Defaults to sts:AssumeRole; Pod Identity needs ["sts:AssumeRole","sts:TagSession"].
    trust_actions = optional(list(string), ["sts:AssumeRole"])
    trust_conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
    # Additional trust statements, OR-ed with the primary one above. Use when a role must trust a second
    # principal under DIFFERENT conditions — e.g. PlatformDeployer's primary statement is SSO-admin-only, but
    # it must ALSO admit the ARC runner role (no SSO condition). Same principal/condition shape as above.
    extra_trust_statements = optional(list(object({
      actions    = optional(list(string), ["sts:AssumeRole"])
      principals = map(list(string))
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
    managed_policies = optional(list(string), [])
    inline_policies  = optional(map(string), {})
    tags             = optional(map(string), {}) # merged onto var.tags (e.g. { Team = "alpha" })
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
