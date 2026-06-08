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

variable "component_resources" {
  description = <<-DESC
    Per-component resource requests/limits for the ArgoCD pods (controller, server, repoServer, applicationSet,
    redis). The upstream chart ships NONE, so on a packed/small cluster the bursty application-controller can be
    CPU-starved under contention → a sluggish UI. Defaults set modest requests to GUARANTEE a baseline and
    deliberately set NO cpu limit (a cpu limit would throttle the controller's reconcile/cache-rebuild bursts).
    Override per component as needed; an omitted component falls back to no resources (chart default).
  DESC
  type = map(object({
    requests = optional(map(string), {})
    limits   = optional(map(string), {})
  }))
  default = {
    controller     = { requests = { cpu = "250m", memory = "512Mi" } }
    server         = { requests = { cpu = "100m", memory = "128Mi" } }
    repoServer     = { requests = { cpu = "100m", memory = "256Mi" } }
    applicationSet = { requests = { cpu = "50m", memory = "128Mi" } }
    redis          = { requests = { cpu = "50m", memory = "64Mi" } }
  }
}

variable "metrics_enabled" {
  description = "Enable per-component Prometheus metrics Services + ServiceMonitors (controller/server/repoServer/applicationSet). Requires the Prometheus-operator CRDs (the observability hub, #102). Off by default."
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
  description = "OIDC scopes to inspect for RBAC (e.g., '[groups]' for named group claims)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# OIDC client-secret ExternalSecret
# Pulls an OIDC client secret from AWS Secrets Manager into a Secret labeled `app.kubernetes.io/part-of: argocd`
# so argocd-cm can reference it as `$<oidc_k8s_secret_name>:<oidc_k8s_secret_key>`. Generic (any OIDC provider);
# used for the Keycloak SSO cutover (ADR-053/059). Requires External Secrets + a ClusterSecretStore.
# ---------------------------------------------------------------------------

variable "oidc_external_secret_enabled" {
  description = "Create the OIDC client-secret ExternalSecret (for SSO via Keycloak/any OIDC IdP)."
  type        = bool
  default     = false
}

variable "oidc_secret_store_name" {
  description = "ClusterSecretStore name External Secrets reads from."
  type        = string
  default     = "aws-secrets-manager"
}

variable "oidc_secret_manager_key" {
  description = "AWS Secrets Manager secret name/path holding the OIDC client secret (e.g. platform/keycloak/argocd-oidc)."
  type        = string
  default     = ""
}

variable "oidc_secret_manager_property" {
  description = "JSON property within the Secrets Manager secret holding the client secret."
  type        = string
  default     = "client-secret"
}

variable "oidc_k8s_secret_name" {
  description = "Name of the synced Kubernetes Secret (referenced from argocd-cm as $<name>:<key>)."
  type        = string
  default     = "argocd-keycloak-oidc"
}

variable "oidc_k8s_secret_key" {
  description = "Key in the synced Kubernetes Secret (the part after the colon in the argocd-cm $ref)."
  type        = string
  default     = "client-secret"
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
