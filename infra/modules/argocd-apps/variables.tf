variable "create" {
  description = "Whether to create ArgoCD app resources"
  type        = bool
  default     = true
}

variable "tenants" {
  description = "Map of tenant names to their apps and isolation mode"
  type = map(object({
    mode      = optional(string, "namespace")
    namespace = optional(string)
    # Tier-1/2 route aliases declared in the team's XTenant claim (spec.domains[].host, ADR-061). Unioned
    # with the generated host and injected into the app's HTTPRoute. Sourced from the claim, not teams.hcl.
    domains = optional(list(string), [])
    apps = map(object({
      repo_url    = string
      repo_path   = optional(string, "k8s/preprod")
      repo_branch = optional(string, "main")
      preview     = optional(bool, false)
    }))
  }))
  default = {}
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

variable "auto_sync" {
  description = "Enable automated sync with self-heal and prune"
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub org for PR preview generators"
  type        = string
  default     = ""
}

variable "ecr_registry" {
  description = "ECR registry URL (e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com)"
  type        = string
  default     = ""
}

variable "preview_domain" {
  description = "Base domain for PR preview hostnames (e.g. preprod.aws.refplat.org)"
  type        = string
  default     = ""
}

variable "preview_pr_labels" {
  description = <<-DESC
    Labels a PR must carry for the PR generator to create a preview environment (ApplicationSet pullRequest
    `github.labels` — ALL must be present). Makes previews OPT-IN: only PRs explicitly labeled get an env, so
    routine PRs (notably Dependabot dependency bumps, which build no app image and would just fail the
    cosign/hostname policy gates) don't spawn failing preview Applications. Empty = preview every open PR.
  DESC
  type        = list(string)
  default     = ["preview"]
}

variable "github_token_secret_name" {
  description = "Name of the Kubernetes Secret in the ArgoCD namespace containing the GitHub PAT (key: token)"
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
# Tenant-claim delivery (BACK stack Phase 1): ArgoCD syncs XTenant claim YAMLs
# ---------------------------------------------------------------------------

variable "enable_tenant_claims" {
  description = "Create the platform-tenants AppProject + Application that syncs Crossplane XTenant claim YAMLs from git to the target cluster (replaces the tenant-claims Terragrunt unit)."
  type        = bool
  default     = false
}

variable "tenant_claims_repo_url" {
  description = "Git repo URL holding the XTenant claim YAMLs (the platform repo)."
  type        = string
  default     = ""
}

variable "tenant_claims_repo_branch" {
  description = "Branch/revision for the claims repo."
  type        = string
  default     = "main"
}

variable "tenant_claims_repo_path" {
  description = "Path within the claims repo to the XTenant YAMLs for the target cluster (e.g. gitops/tenant-claims/preprod)."
  type        = string
  default     = "gitops/tenant-claims/preprod"
}
