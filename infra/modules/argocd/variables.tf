variable "create" {
  description = "Controls whether ArgoCD resources should be created"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for IAM role naming)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# IRSA
# ---------------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA. Empty string disables IRSA."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (without https:// prefix) for IRSA trust policy"
  type        = string
  default     = ""
}

variable "extra_iam_policy_arns" {
  description = "Additional IAM policy ARNs to attach to the ArgoCD IRSA role"
  type        = list(string)
  default     = []
}

variable "remote_cluster_role_arns" {
  description = "Cross-account IAM role ARNs that ArgoCD needs to assume for remote cluster management"
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "argocd"
}

variable "helm_repository" {
  description = "Repository URL for the ArgoCD Helm chart"
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}

variable "helm_chart" {
  description = "Name of the Helm chart"
  type        = string
  default     = "argo-cd"
}

variable "helm_chart_version" {
  description = "Version of the ArgoCD Helm chart"
  type        = string
  default     = "9.5.14"
}

variable "namespace" {
  description = "Kubernetes namespace to install ArgoCD into"
  type        = string
  default     = "argocd"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 900
}

variable "helm_wait" {
  description = "Whether to wait for Helm release to complete"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# ArgoCD configuration
# ---------------------------------------------------------------------------

variable "high_availability" {
  description = "Deploy ArgoCD in HA mode (2 replicas per component)"
  type        = bool
  default     = false
}

variable "server_insecure" {
  description = "Run ArgoCD server without TLS (for use behind a TLS-terminating proxy or port-forward)"
  type        = bool
  default     = true
}

variable "server_service_type" {
  description = "Kubernetes service type for the ArgoCD server"
  type        = string
  default     = "ClusterIP"
}

variable "reconciliation_timeout" {
  description = "How often ArgoCD re-syncs applications"
  type        = string
  default     = "180s"
}

variable "dex_enabled" {
  description = "Enable Dex SSO server"
  type        = bool
  default     = false
}

variable "notifications_enabled" {
  description = "Enable ArgoCD notifications controller"
  type        = bool
  default     = false
}

variable "applicationset_enabled" {
  description = "Enable ApplicationSet controller"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# RBAC
# ---------------------------------------------------------------------------

variable "rbac_default_policy" {
  description = "Default RBAC policy (role:readonly, role:admin, or empty)"
  type        = string
  default     = "role:readonly"
}

variable "rbac_policy_csv" {
  description = "RBAC policy rules in ArgoCD CSV format"
  type        = string
  default     = <<-CSV
    p, role:org-admin, applications, *, */*, allow
    p, role:org-admin, clusters, get, *, allow
    p, role:org-admin, repositories, *, *, allow
    p, role:org-admin, logs, get, *, allow
    p, role:org-admin, exec, create, */*, allow
    g, org-admin, role:org-admin
  CSV
}

variable "rbac_scopes" {
  description = "OIDC scopes to inspect for RBAC (e.g., '[groups]' for Dex group claims)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Repositories and credentials
# ---------------------------------------------------------------------------

variable "repositories" {
  description = "Repository credentials for ArgoCD (map of repo objects)"
  type        = any
  default     = {}
}

variable "credential_templates" {
  description = "Credential templates for repo pattern matching"
  type        = any
  default     = {}
}

# ---------------------------------------------------------------------------
# Projects and resource exclusions
# ---------------------------------------------------------------------------

variable "projects" {
  description = "ArgoCD project definitions"
  type        = any
  default     = {}
}

variable "resource_exclusions" {
  description = "Resources ArgoCD should ignore (list of {apiGroups, kinds, clusters})"
  type        = any
  # CiliumIdentity resources are high-churn and auto-managed by the Cilium agent;
  # tracking them causes excessive ArgoCD reconciliation noise
  default = [
    {
      apiGroups = ["cilium.io"]
      kinds     = ["CiliumIdentity"]
      clusters  = ["*"]
    }
  ]
}

variable "argocd_cm_extra" {
  description = "Additional key-value pairs to merge into argocd-cm ConfigMap"
  type        = map(string)
  default     = {}
}
