variable "create" {
  description = "Whether to manage org teams and repo grants."
  type        = bool
  default     = true
}

variable "teams" {
  description = <<-EOT
    Org teams to manage, keyed by team name (== the GitHub team slug; our team names are slug-safe). One per
    entry in the Team registry (gitops/teams/). Each team is created as the native ownership layer for its app
    repos (ADR-072). `privacy` is "closed" (visible to all org members) by default.
  EOT
  type = map(object({
    description = optional(string)
    privacy     = optional(string, "closed")
  }))
  default = {}
}

variable "repo_grants" {
  description = <<-EOT
    Repo write-access grants, keyed by repo name (<team>-<product>, org-unique by construction). One per Product
    (gitops/products/) — its owning team gets `push` (Members: write) on its repo. The team must appear in
    var.teams (the grant references the managed team, creating the team→grant dependency). The repo must already
    exist (New Product creates it eagerly before the registry PR merges).
  EOT
  type = map(object({
    team       = string
    repo       = string
    permission = optional(string, "push")
  }))
  default = {}
}
