variable "create" {
  description = "Whether to deploy oauth2-proxy"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Helm chart (oauth2-proxy/oauth2-proxy)
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also the Service name and the assembled K8s Secret name)"
  type        = string
  default     = "oauth2-proxy"
}

variable "helm_repository" {
  description = "Helm chart repository"
  type        = string
  default     = "https://oauth2-proxy.github.io/manifests"
}

variable "helm_chart" {
  description = "Helm chart name"
  type        = string
  default     = "oauth2-proxy"
}

variable "helm_chart_version" {
  description = "Helm chart version (pinned in _versions.hcl). MUST resolve to appVersion >= 7.15.2 (CVE-2026-40575)."
  type        = string
}

variable "namespace" {
  description = "Namespace to deploy into. Shares the backstage namespace (owned by the backstage module) so the gateway route backend stays same-namespace. This module does NOT create it."
  type        = string
  default     = "backstage"
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds)"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready. Default false: the client secret is synced async by External Secrets, so the pod may briefly wait on it; verify health out of band."
  type        = bool
  default     = false
}

variable "replica_count" {
  description = "oauth2-proxy replicas. 2+ for HA — cookie session storage is stateless, so any replica validates any cookie as long as they share the cookie-secret (they do)."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# OIDC / proxy behavior
# ---------------------------------------------------------------------------

variable "oidc_issuer_url" {
  description = "OIDC issuer the proxy fetches discovery from + does the code exchange against. Keycloak realm by default (the IdP of record, ADR-053/059); was Dex pre-cutover."
  type        = string
  default     = "https://sso.aws.refplat.org"
}

variable "oidc_client_id" {
  description = "OIDC client id — must match the IdP client (the keycloak-config `oauth2-proxy` client)."
  type        = string
  default     = "oauth2-proxy"
}

variable "app_host" {
  description = "Public hostname of the protected app (Backstage). Used for the redirect URL, cookie domain, and redirect whitelist."
  type        = string
  default     = "backstage.aws.refplat.org"
}

variable "upstream_service" {
  description = "In-namespace Service oauth2-proxy proxies authenticated traffic to (Backstage)."
  type        = string
  default     = "backstage"
}

variable "upstream_port" {
  description = "Upstream Service port (Backstage backend)."
  type        = number
  default     = 7007
}

variable "service_port" {
  description = "oauth2-proxy Service port (== the gateway-config route backend port; the container listens on this)."
  type        = number
  default     = 4180
}

variable "cookie_expire" {
  description = "Session cookie lifetime before a forced re-login. cookie-refresh is hard-set to 0 (no upstream refresh token exists — #202), so this is the whole session length."
  type        = string
  default     = "24h"
}

variable "email_domains" {
  description = "Email domains allowed to authenticate. '*' = any identity the IdP (Keycloak) authenticates; the real authZ gate is realm membership / the app's own RBAC."
  type        = list(string)
  default     = ["*"]
}

variable "host_aliases" {
  description = "Pod hostAliases — resolve the OIDC issuer host to the in-cluster gateway ClusterIP so proxy<->IdP traffic stays in-cluster (same split-horizon as the backstage unit)."
  type = list(object({
    ip        = string
    hostnames = list(string)
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

variable "client_secret_name" {
  description = "Secrets Manager path holding the OIDC client secret (the keycloak-config `oauth2-proxy` client writes platform/keycloak/oauth2-proxy-oidc)."
  type        = string
  default     = "platform/oauth2-proxy/oidc"
}

variable "client_secret_key" {
  description = "Key/property within the OIDC Secrets Manager secret."
  type        = string
  default     = "client-secret"
}

variable "secret_store_name" {
  description = "Name of the ClusterSecretStore (External Secrets) to read Secrets Manager."
  type        = string
  default     = "aws-secrets-manager"
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window for the generated cookie secret. 0 = force-delete (setup-friendly); raise for prod."
  type        = number
  default     = 0
}

variable "resources" {
  description = "oauth2-proxy container resource requests/limits"
  type = object({
    requests = optional(map(string), { cpu = "25m", memory = "64Mi" })
    limits   = optional(map(string), { cpu = "100m", memory = "128Mi" })
  })
  default = {}
}

variable "tags" {
  description = "Tags (applied to the Secrets Manager secret; rendered as pod labels)"
  type        = map(string)
  default     = {}
}
