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

variable "github_token_secret_name" {
  description = "Name of the Kubernetes Secret in the ArgoCD namespace containing the GitHub PAT (key: token)"
  type        = string
  default     = ""
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
