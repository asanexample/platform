variable "create" {
  description = "Whether to create any resources in this module."
  type        = bool
  default     = true
}

variable "permission_sets" {
  description = "Map of permission set names to their configuration."
  type = map(object({
    description      = optional(string, "")
    session_duration = optional(string, "PT4H")
    managed_policies = optional(list(string), [])
    inline_policy    = optional(string)
  }))
  default = {}
}

variable "groups" {
  description = "Map of group names to their configuration."
  type = map(object({
    description = optional(string, "")
  }))
  default = {}
}

variable "users" {
  description = "Map of usernames to their configuration."
  type = map(object({
    given_name   = string
    family_name  = string
    email        = string
    display_name = optional(string)
    groups       = optional(list(string), [])
  }))
  default = {}
}

variable "account_assignments" {
  description = "List of group-to-account permission set assignments."
  type = list(object({
    account_id     = string
    permission_set = string
    group          = string
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to permission sets."
  type        = map(string)
  default     = {}
}
