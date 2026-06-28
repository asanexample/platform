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
  description = "Optional base domain. When set, the per-Product delivery ApplicationSet rewrites each Environment's HTTPRoute hostname to <product>-<team>-<stage>.<preview_domain> (a per-stage host rewrite — NOT per-PR previews; those, ADR-032, are not yet implemented on the v3 model)."
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

variable "enable_roles" {
  description = "Create the platform-roles AppProject + Application that syncs the git-native WorkforceRole catalog (gitops/roles) to the target cluster as a read-only projection (ADR-088 — the activation operator reads the borrow cap + permission set from it)."
  type        = bool
  default     = false
}

variable "roles_repo_url" {
  description = "Git repo URL holding the WorkforceRole CR YAMLs (the platform repo)."
  type        = string
  default     = ""
}

variable "roles_repo_branch" {
  description = "Branch/revision for the WorkforceRole CRs repo."
  type        = string
  default     = "main"
}

variable "roles_repo_path" {
  description = "Path within the repo to the WorkforceRole CR YAMLs (e.g. gitops/roles)."
  type        = string
  default     = "gitops/roles"
}

# ---------------------------------------------------------------------------
# delivery (ADR-069 / L2b #384) — per-Product ApplicationSets from the git registry
# ---------------------------------------------------------------------------
variable "products" {
  description = "v3: per-Product delivery, keyed <team>-<product>. One ApplicationSet per product; its git-files generator fans out over the Product's Release records gitops/releases/<team>/<product>/*.yaml → one Application per Environment that has a Release (ADR-071, #377)."
  type = map(object({
    team     = string # owning team
    product  = string # product short name (the gitops/{releases,environments}/<team>/<product>/ dir)
    repo_url = string # the app repo (Product.repo), https URL — the Application source
  }))
  default = {}
}

variable "platform_repo_url" {
  description = "v3: the platform GitOps repo read by the registry-sync apps (gitops/{products,environments,grants}/) and the per-Product delivery ApplicationSet (gitops/releases/<team>/<product>/). Empty disables delivery."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Platform-agent delivery (ADR-082) — the agents registry-sync + per-agent workload ApplicationSet, on the HUB
# ---------------------------------------------------------------------------
variable "agents" {
  description = "ADR-082: platform agents keyed by XAgent name. Their WORKLOAD is delivered to the HUB (hub_cluster_server) into the Composition-made namespace platform-agent-<name>; their identity/RBAC come from the XAgent Composition (not ArgoCD). product_key is the gitops/products registry key (<team>-<product>), used to EXCLUDE the agent's Product from the preprod per-Product delivery (it ships to the hub instead)."
  type = map(object({
    team        = string # owning team (platform)
    product     = string # product short name (drives the ECR image team-<team>/<product>-<svc>)
    product_key = string # the gitops/products registry key <team>-<product> (the var.products key to exclude)
    repo_url    = string # the app repo (Product.repo), https URL — the Application source
  }))
  default = {}
}

variable "hub_cluster_server" {
  description = "ADR-082: the in-cluster (hub) API server the agent control plane + workloads target. ArgoCD's built-in in-cluster (https://kubernetes.default.svc) — the platform cluster ArgoCD itself runs on. The agent control plane lives on the hub (ADR-048-consistent), unlike tenant delivery which targets the preprod workload cluster (cluster_server)."
  type        = string
  default     = "https://kubernetes.default.svc"
}

variable "platform_repo_branch" {
  description = "v3: branch of the platform GitOps repo the registry-sync apps + the per-Product ApplicationSet track."
  type        = string
  default     = "main"
}

variable "ecr_registry" {
  description = "ECR registry host for the per-Product image (ADR-071). The ApplicationSet injects the Release digest as a kustomize image override whose name must match the app overlay's image — <ecr_registry>/team-<team>/<product>-<service>."
  type        = string
  default     = ""
}
