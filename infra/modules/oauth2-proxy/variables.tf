variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "name" {
  description = "Instance name — used for the release, Service, and synced Secret (e.g. \"rollouts\"). Lets one cluster front several UIs."
  type        = string
}

variable "namespace" {
  description = "Namespace to deploy into — normally the UPSTREAM's namespace, so the proxy reaches it in-cluster (e.g. \"argo-rollouts\")."
  type        = string
}

# ---------------------------------------------------------------------------
# Upstream (the unauthenticated UI being fronted)
# ---------------------------------------------------------------------------

variable "upstream_url" {
  description = "In-cluster URL of the UI to protect, e.g. http://argo-rollouts-dashboard.argo-rollouts.svc:3100. All requests pass through oauth2-proxy after auth."
  type        = string
}

variable "external_url" {
  description = "Public (browser) base URL the proxy is reached at, e.g. https://rollouts.aws.refplat.org. Drives the OIDC redirect-url (<external_url>/oauth2/callback) and the cookie domain."
  type        = string
}

# ---------------------------------------------------------------------------
# OIDC (Keycloak)
# ---------------------------------------------------------------------------

variable "oidc_issuer_url" {
  description = "OIDC issuer, e.g. https://keycloak.aws.refplat.org/realms/platform."
  type        = string
}

variable "oidc_client_id" {
  description = "Keycloak confidential client id (registered in keycloak-config)."
  type        = string
}

variable "oidc_client_secret_sm_key" {
  description = "Secrets Manager key holding the OIDC client secret (keycloak-config `client_secret_names[<client>]`), synced in via ESO."
  type        = string
}

variable "secret_store_name" {
  description = "ESO ClusterSecretStore name used to sync the client secret from Secrets Manager."
  type        = string
}

variable "oidc_client_secret_sm_property" {
  description = "JSON property to extract from the SM secret. keycloak-config stores clients as {\"client-secret\":\"...\"}, so the bare secret is the `client-secret` property (NOT the whole blob)."
  type        = string
  default     = "client-secret"
}

variable "allowed_groups" {
  description = "Keycloak group memberships allowed in (oauth2-proxy `--allowed-group`). Empty = any authenticated realm user (still gated by `email_domains`). Requires a `groups` claim mapper on the client."
  type        = list(string)
  default     = []
}

variable "email_domains" {
  description = "Permitted email domains (oauth2-proxy `--email-domain`). \"*\" = any verified email; the realm itself is the trust boundary."
  type        = list(string)
  default     = ["*"]
}

# ---------------------------------------------------------------------------
# Split-horizon host-alias — make the proxy's BACKEND OIDC calls to the issuer
# host resolve to the gateway Envoy ClusterIP (bypass the internal-NLB hairpin,
# same trick as Grafana/Backstage). Only needed when the issuer is served by THIS
# cluster's gateway (the hub); cross-cluster spokes reach it over TGW normally.
# ---------------------------------------------------------------------------

variable "issuer_host_alias" {
  description = "Hostname of the issuer to pin to the local gateway Envoy ClusterIP (e.g. keycloak.aws.refplat.org). Empty = no host-alias (spoke clusters reaching the hub issuer over TGW)."
  type        = string
  default     = ""
}

variable "gateway_service_name" {
  description = "Gateway-API (Cilium) Envoy Service name to resolve for the host-alias ClusterIP. Only used when issuer_host_alias is set."
  type        = string
  default     = "cilium-gateway-platform-gateway"
}

variable "gateway_service_namespace" {
  description = "Namespace of the gateway Envoy Service. Only used when issuer_host_alias is set."
  type        = string
  default     = "default"
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_chart_version" {
  description = "oauth2-proxy chart version (oauth2-proxy/oauth2-proxy)."
  type        = string
  default     = "7.8.2"
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags (sanitized into K8s labels)."
  type        = map(string)
  default     = {}
}
