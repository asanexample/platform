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
    trust_principals     = map(list(string))
    trust_conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
    managed_policies = optional(list(string), [])
    inline_policies  = optional(map(string), {})
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
