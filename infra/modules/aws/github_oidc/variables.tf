variable "create" {
  description = "Whether to create the OIDC provider and role"
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (use github_repos for multiple)"
  type        = string
  default     = ""
}

variable "github_repos" {
  description = "List of GitHub repository names allowed to assume the role"
  type        = list(string)
  default     = []
}

variable "github_branches" {
  description = "List of branch patterns allowed to assume the role (e.g. [\"main\", \"refs/heads/feat/*\"])"
  type        = list(string)
  default     = ["main"]
}

variable "github_events" {
  description = "GitHub event types to allow (e.g. [\"pull_request\"])"
  type        = list(string)
  default     = []
}

variable "role_name" {
  description = "Name of the IAM role to create"
  type        = string
}

variable "role_policy_arns" {
  description = "List of managed IAM policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "inline_policy" {
  description = "Optional inline IAM policy JSON to attach to the role"
  type        = string
  default     = ""
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds for the role"
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
