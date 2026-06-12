variable "create" {
  description = "Whether to create ArgoCD app resources"
  type        = bool
  default     = true
}

variable "cluster_server" {
  description = "API server URL of the target cluster"
  type        = string
  default     = ""
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "preview_domain" {
  description = "Base domain for PR preview hostnames (e.g. preprod.aws.refplat.org)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Git-native Team delivery (ADR-063): ArgoCD syncs Team CRs from git
# ---------------------------------------------------------------------------

variable "enable_teams" {
  description = "Create the platform-teams AppProject + Application that syncs git-native Team CRs to the target cluster (replaces the crossplane-teams Helm projection, ADR-063)."
  type        = bool
  default     = false
}

variable "teams_repo_url" {
  description = "Git repo URL holding the Team CR YAMLs (the platform repo)."
  type        = string
  default     = ""
}

variable "teams_repo_branch" {
  description = "Branch/revision for the Team CRs repo."
  type        = string
  default     = "main"
}

variable "teams_repo_path" {
  description = "Path within the repo to the Team CR YAMLs (e.g. gitops/teams)."
  type        = string
  default     = "gitops/teams"
}

# ---------------------------------------------------------------------------
# v3 delivery (ADR-069 / L2b #384) — per-Product ApplicationSets from the git registry
# ---------------------------------------------------------------------------
variable "products" {
  description = "v3: per-Product delivery, keyed <team>-<product>. One ApplicationSet per product; its git-files generator fans out over gitops/environments/<team>/<product>/*.yaml → one Application per Environment (decision c)."
  type = map(object({
    team     = string # owning team
    product  = string # product short name (the gitops/environments/<team>/<product>/ dir)
    repo_url = string # the app repo (Product.repo), https URL — the Application source
  }))
  default = {}
}

variable "platform_repo_url" {
  description = "v3: the platform GitOps repo the per-Product ApplicationSet git-files generator reads Environment claims from (gitops/environments/). Empty disables v3 delivery."
  type        = string
  default     = ""
}

variable "platform_repo_branch" {
  description = "v3: branch of the platform GitOps repo the registry-sync apps + the per-Product ApplicationSet track."
  type        = string
  default     = "main"
}
