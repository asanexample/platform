variable "create" {
  description = "Whether to create ECR repositories"
  type        = bool
  default     = true
}

variable "repositories" {
  description = "Map of repository names to configuration. Keys are repo names (e.g. 'team-alpha/app')."
  type = map(object({
    tag_mutability = optional(string, "IMMUTABLE")
    tags           = optional(map(string), {}) # merged onto var.tags (e.g. { Team = "alpha" })
  }))
  default = {}
}

variable "pull_account_ids" {
  description = "AWS account IDs allowed to pull images cross-account"
  type        = list(string)
  default     = []
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain per repository"
  type        = number
  default     = 50
}

variable "force_delete" {
  description = "Whether to allow deletion of non-empty repositories"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
