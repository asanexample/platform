variable "create" {
  description = "Controls whether resources are created (the P13 read-isolation toggle — enable_per_team_tenants)."
  type        = bool
  default     = false
}

variable "name" {
  description = "Instance name (Deployment/Service/selector). One proxy per signal — `tenant-proxy` (metrics), `loki-tenant-proxy` (logs), `tempo-tenant-proxy` (traces), `pyroscope-tenant-proxy` (profiles) — each fronting its store via `upstream_url`. The resolver/grant logic is identical; only the upstream differs."
  type        = string
  default     = "tenant-proxy"
}

variable "namespace" {
  description = "Namespace to deploy into (the shared observability namespace, next to Grafana + Mimir)."
  type        = string
  default     = "observability"
}

variable "image" {
  description = "The signed tenant-proxy image, digest-pinned (registry/repo@sha256:…). Built by tenant-proxy-image.yml, ADR-071 digest-pin."
  type        = string
}

variable "replicas" {
  description = "tenant-proxy replicas. On the read path, so run >=2."
  type        = number
  default     = 2
}

variable "upstream_url" {
  description = "The store query API the proxy reverse-proxies to (per-request X-Scope-OrgID). The in-cluster Mimir gateway /prometheus."
  type        = string
  default     = "http://mimir-gateway.observability.svc/prometheus"
}

variable "jwks_url" {
  description = "Keycloak realm JWKS endpoint. Use the IN-CLUSTER keycloak service to avoid the in-cluster→internal-NLB hairpin — the token's `iss` (oidc_issuer) is still the public realm URL, checked independently of where the keys are fetched."
  type        = string
  default     = "http://keycloak-http.keycloak.svc/realms/platform/protocol/openid-connect/certs"
}

variable "oidc_issuer" {
  description = "The exact `iss` the token must carry — the PUBLIC realm URL Keycloak stamps into tokens."
  type        = string
  default     = "https://keycloak.aws.refplat.org/realms/platform"
}

variable "oidc_audience" {
  description = "The `aud` the token must contain — the Grafana OIDC client id."
  type        = string
  default     = "grafana"
}

variable "userinfo_url" {
  description = "Keycloak realm userinfo endpoint. Enables the robust identity fallback: when Grafana's oauthPassThru drops the X-Id-Token (a Grafana 13 regression), the proxy resolves the caller's groups from this endpoint using the still-forwarded Authorization Bearer access token. Same in-cluster keycloak service as jwks_url (same egress path, no netpol change). Set to \"\" to disable the fallback (id_token-only)."
  type        = string
  default     = "http://keycloak-http.keycloak.svc/realms/platform/protocol/openid-connect/userinfo"
}

variable "userinfo_cache_ttl" {
  description = "How long a userinfo lookup is cached per access token (Go duration, e.g. \"30s\"). Empty → the proxy's built-in default (30s). Keep short so a revoked token stops working quickly."
  type        = string
  default     = ""
}

variable "tenants" {
  description = "Known team tenants the proxy may scope to (comma-joined into the proxy's TENANTS). A user's groups are intersected with this set; unknown groups can't widen access."
  type        = list(string)
  default     = ["alpha", "bravo", "platform"]
}

variable "admin_group" {
  description = "The group granting the federated all-tenant read (platform-admins → sees every tenant)."
  type        = string
  default     = "platform-admins"
}

variable "grants" {
  description = "Cross-team read grants (ADR-068 AccessGrant projection): grantee team group → the owner tenants it may ADDITIONALLY read on top of its own. E.g. { bravo = [\"alpha\"] } lets group `bravo` read alpha's tenant (federated `X-Scope-OrgID: alpha|bravo`). Rendered into the proxy's GRANTS env; the proxy drops any owner that isn't a known tenant (a grant never invents a scope). Derived at the unit from gitops/grants, excluding regulated (pci/hipaa) targets. Empty = no cross-team sharing (own-tenant-only)."
  type        = map(list(string))
  default     = {}
}

variable "create_datasource" {
  description = "Create the per-team Grafana datasource ConfigMap (oauthPassThru → the proxy). True on the hub that runs Grafana."
  type        = bool
  default     = true
}

variable "datasource_name" {
  description = "Display name of the per-team Grafana datasource."
  type        = string
  default     = "Mimir (my team)"
}

variable "create_service_monitor" {
  description = "Scrape the proxy's own decision metrics (tenant_proxy_requests_total)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Labels to apply."
  type        = map(string)
  default     = {}
}
