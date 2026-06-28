locals {
  create = var.create

  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  secret_name   = "${var.name}-oauth2-proxy"
  cookie_domain = replace(replace(var.external_url, "https://", ""), "http://", "")
  use_alias     = var.issuer_host_alias != ""
  oidc_scope    = length(var.allowed_groups) > 0 ? "openid email profile groups" : "openid email profile"

  # oauth2-proxy config (cfg form — handles list values cleanly; the client id/secret + cookie secret arrive via
  # the existingSecret as env, NOT here). `reverse_proxy` + `set_xauthrequest` so it proxies the upstream after auth.
  config_file = join("\n", concat([
    "provider = \"oidc\"",
    "oidc_issuer_url = \"${var.oidc_issuer_url}\"",
    "redirect_url = \"${var.external_url}/oauth2/callback\"",
    "upstreams = [\"${var.upstream_url}\"]",
    "email_domains = ${jsonencode(var.email_domains)}",
    "scope = \"${local.oidc_scope}\"",
    "cookie_secure = true",
    "cookie_domains = [\"${local.cookie_domain}\"]",
    "whitelist_domains = [\"${local.cookie_domain}\"]",
    "http_address = \"0.0.0.0:4180\"",
    "reverse_proxy = true",
    "set_xauthrequest = true",
    "pass_access_token = true",
    "skip_provider_button = true",
    ], length(var.allowed_groups) > 0 ? [
    "allowed_groups = ${jsonencode(var.allowed_groups)}"
  ] : []))
}

# Gateway Envoy ClusterIP for the split-horizon host-alias (only when the issuer is served by THIS cluster's
# gateway — the hub). Looked up, never hardcoded (mirrors the observability/Grafana pattern).
data "kubernetes_service_v1" "gateway" {
  count = local.create && local.use_alias ? 1 : 0

  metadata {
    name      = var.gateway_service_name
    namespace = var.gateway_service_namespace
  }
}

# Cookie signing secret — generated, not sourced from Keycloak. 32 bytes = AES-256 for the encrypted session cookie.
resource "random_password" "cookie" {
  count   = local.create ? 1 : 0
  length  = 32
  special = false
}

# The proxy's Secret: OIDC client-secret synced from Secrets Manager (ESO), client-id + cookie-secret templated in.
# oauth2-proxy reads all three via `config.existingSecret`.
resource "kubernetes_manifest" "secret" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.secret_name
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target = {
        name           = local.secret_name
        creationPolicy = "Owner"
        template = {
          engineVersion = "v2"
          metadata      = { labels = merge(local.k8s_labels, { "app.kubernetes.io/managed-by" = "oauth2-proxy-module" }) }
          data = {
            "client-id"     = var.oidc_client_id
            "cookie-secret" = random_password.cookie[0].result
            "client-secret" = "{{ .clientSecret }}"
          }
        }
      }
      data = [{
        secretKey = "clientSecret"
        # keycloak-config stores the secret as JSON {"client-secret":"..."} — extract the property, not the blob.
        remoteRef = { key = var.oidc_client_secret_sm_key, property = var.oidc_client_secret_sm_property }
      }]
    }
  }
}

resource "helm_release" "this" {
  count = local.create ? 1 : 0

  name       = var.name
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = var.helm_chart_version
  namespace  = var.namespace

  wait    = var.helm_wait
  timeout = 600

  values = [yamlencode({
    # Name the chart's resources exactly `var.name` (e.g. Service `rollouts`) instead of the chart default
    # `<release>-oauth2-proxy`, so the gateway-config route's backend Service name matches (= module output).
    fullnameOverride = var.name

    config = {
      existingSecret = local.secret_name
      configFile     = local.config_file
    }

    podLabels = local.k8s_labels

    # Split-horizon: pin the issuer host to the gateway Envoy ClusterIP so backend OIDC calls don't hairpin the NLB.
    hostAliases = local.use_alias ? [{
      ip        = data.kubernetes_service_v1.gateway[0].spec[0].cluster_ip
      hostnames = [var.issuer_host_alias]
    }] : []

    # Kyverno-compliant (restricted PSA): non-root, no priv-esc, RO rootfs, drop ALL, RuntimeDefault.
    securityContext = {
      runAsNonRoot             = true
      allowPrivilegeEscalation = false
      readOnlyRootFilesystem   = true
      capabilities             = { drop = ["ALL"] }
      seccompProfile           = { type = "RuntimeDefault" }
    }

    resources = {
      requests = { cpu = "10m", memory = "32Mi" }
      limits   = { cpu = "100m", memory = "128Mi" }
    }
  })]

  depends_on = [kubernetes_manifest.secret]
}
