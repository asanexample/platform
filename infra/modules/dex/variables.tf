variable "create" {
  description = "Whether to deploy Dex"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Helm chart (dexidp/dex — the centralized SAML->OIDC broker, ADR-052)
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also the Service name)"
  type        = string
  default     = "dex"
}

variable "helm_repository" {
  description = "Helm chart repository"
  type        = string
  default     = "https://charts.dexidp.io"
}

variable "helm_chart" {
  description = "Helm chart name"
  type        = string
  default     = "dex"
}

variable "helm_chart_version" {
  description = "Helm chart version (pinned in _versions.hcl)"
  type        = string
}

variable "namespace" {
  description = "Namespace for Dex"
  type        = string
  default     = "dex"
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds)"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready. Default false: the OIDC client secret is synced async by External Secrets, so the pod may briefly wait on it; verify health out of band."
  type        = bool
  default     = false
}

variable "replica_count" {
  description = "Dex replicas. 2+ for stateless HA (storage is kubernetes/CRD-backed, shared across replicas)."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# Image (upstream ghcr.io/dexidp/dex — not our ECR, so NOT cosign-signed by us;
# pinned to the chart's appVersion via the pinned chart, with optional digest pin)
# ---------------------------------------------------------------------------

variable "image_repository" {
  description = "Dex image repository"
  type        = string
  default     = "ghcr.io/dexidp/dex"
}

variable "image_tag" {
  description = "Dex image tag. Empty inherits the pinned chart's appVersion (the supply-chain pin); set to override."
  type        = string
  default     = ""
}

variable "image_digest" {
  description = "Optional image digest (sha256:...) to pin by digest instead of tag. See docs/runbooks/dex-sso.md for how to resolve it."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# OIDC issuer + clients
# ---------------------------------------------------------------------------

variable "dex_issuer" {
  description = "Public OIDC issuer URL (the Dex hostname behind the gateway). The SAML ACS/callback is <issuer>/callback."
  type        = string
  default     = "https://sso.aws.refplat.org"
}

variable "static_clients" {
  description = <<-DESC
    OIDC clients Dex serves. Each gets a generated client secret stored in Secrets Manager at
    platform/<id>/oidc, synced into the dex namespace as the K8s Secret dex-<id>-oidc, and injected
    into Dex via the named env var (referenced by the client's `secretEnv`). Add a client here to
    onboard another app — no other module change needed.
  DESC
  type = list(object({
    id            = string
    name          = string
    redirect_uris = list(string)
    secret_env    = string
  }))
  default = [{
    id            = "backstage"
    name          = "Backstage"
    redirect_uris = ["https://backstage.aws.refplat.org/api/auth/oidc/handler/frame"]
    secret_env    = "BACKSTAGE_CLIENT_SECRET"
  }]
}

# ---------------------------------------------------------------------------
# Identity Center SAML connector (mirrors the ArgoCD pattern; new SAML app -> new cert).
# Values come from secrets.hcl (dex_sso_url / dex_sso_ca_data) via the unit.
# ---------------------------------------------------------------------------

variable "saml_sso_url" {
  description = "Identity Center SAML SSO (IdP) URL for the Dex SAML app."
  type        = string
}

variable "saml_ca_data" {
  description = "Base64 IdP signing certificate for the Dex SAML app (caData)."
  type        = string
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

variable "secret_store_name" {
  description = "Name of the ClusterSecretStore (External Secrets) to read Secrets Manager."
  type        = string
  default     = "aws-secrets-manager"
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window for the generated client secrets. 0 = force-delete (setup-friendly); raise for prod."
  type        = number
  default     = 0
}

variable "resources" {
  description = "Dex container resource requests/limits"
  type = object({
    requests = optional(map(string), { cpu = "50m", memory = "64Mi" })
    limits   = optional(map(string), { cpu = "200m", memory = "128Mi" })
  })
  default = {}
}

variable "tags" {
  description = "Tags (applied to Secrets Manager secrets; rendered as pod labels)"
  type        = map(string)
  default     = {}
}
