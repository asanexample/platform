locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  # The K8s Secret (assembled by the ExternalSecret below) that the chart consumes via
  # config.existingSecret. Required keys: client-id, client-secret, cookie-secret.
  secret_name = var.helm_release_name

  upstream_url = "http://${var.upstream_service}.${var.namespace}.svc.cluster.local:${var.upstream_port}"

  # ---------------------------------------------------------------------------
  # Helm values
  # ---------------------------------------------------------------------------
  values = {
    replicaCount = var.replica_count

    # Image tag empty => the pinned chart's appVersion (the supply-chain pin). Registry default = quay.io.
    image = { pullPolicy = "IfNotPresent" }

    config = {
      existingSecret = local.secret_name
      # alphaConfig is disabled (chart default), so the chart generates oauth2_proxy.cfg from `upstreams`
      # + `emailDomains`; all other flags come from extraArgs. Single upstream = Backstage, same namespace.
      upstreams    = [local.upstream_url]
      emailDomains = var.email_domains
    }

    extraArgs = {
      provider        = "oidc"
      oidc-issuer-url = var.oidc_issuer_url
      redirect-url    = "https://${var.app_host}/oauth2/callback"
      # Durable session: oauth2-proxy owns the cookie and NEVER refreshes against the upstream — SAML/Dex
      # issues no refresh token (#202), so cookie-refresh=0 disables the (doomed) access-token refresh and
      # the cookie stays valid for cookie-expire. This is the whole fix for logout-on-refresh.
      cookie-expire        = var.cookie_expire
      cookie-refresh       = "0"
      cookie-secure        = "true"
      cookie-domain        = var.app_host
      whitelist-domain     = var.app_host # only same-host post-login redirects
      reverse-proxy        = "true"       # behind the Cilium Gateway (Envoy)
      skip-provider-button = "true"       # auto-redirect to Dex, no oauth2-proxy landing page
      # Inject identity for Backstage's oauth2Proxy provider. oauth2-proxy STRIPS any client-supplied
      # X-Forwarded-*/X-Auth-Request-* first, then sets them from the validated session — so only the proxy
      # can set them. Backstage trusts them blindly, so backstage:7007 is ALSO locked to this pod by the
      # backstage chart's NetworkPolicy (ingressRules.podSelector). See #202 / docs/runbooks/dex-sso.md.
      set-xauthrequest  = "true"
      pass-user-headers = "true"
      scope             = "openid profile email"
    }

    # Cookie session storage (no Redis) — stateless across replicas (shared cookie-secret).
    sessionStorage = { type = "cookie" }

    # Service port == the gateway-config route backend port; the container listens on this port.
    service = { portNumber = var.service_port }

    # Resolve the OIDC issuer host to the in-cluster gateway (split-horizon, same as the backstage unit),
    # so the proxy<->Dex OIDC handshake never leaves the cluster.
    hostAliases = var.host_aliases

    resources = var.resources
    podLabels = local.k8s_labels
    # NB: the chart's default container securityContext is already hardened (runAsNonRoot, runAsUser 2000,
    # readOnlyRootFilesystem, drop ALL, seccomp RuntimeDefault) — sufficient for the platform namespace; no
    # override needed. Cookie sessions need no writable filesystem.
  }
}

# ---------------------------------------------------------------------------
# Cookie secret — TF-generated, stored in Secrets Manager (platform/oauth2-proxy/cookie).
# 32 ASCII bytes => AES-256 for oauth2-proxy's encrypted+signed session cookie.
# ---------------------------------------------------------------------------

resource "random_password" "cookie" {
  count = local.create ? 1 : 0

  length  = 32
  special = false # alphanumeric — 32 bytes, safe across the SM->ESO->env path
}

resource "aws_secretsmanager_secret" "cookie" {
  count = local.create ? 1 : 0

  name                    = "platform/${var.helm_release_name}/cookie"
  description             = "oauth2-proxy session cookie secret (AES key for the Backstage auth proxy, #202)."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "cookie" {
  count = local.create ? 1 : 0

  secret_id     = aws_secretsmanager_secret.cookie[0].id
  secret_string = jsonencode({ "cookie-secret" = random_password.cookie[0].result })
}

# ---------------------------------------------------------------------------
# ExternalSecret -> the chart's existingSecret. Assembles all three required keys into one K8s Secret:
#   client-id     — literal (the Dex staticClient id)
#   client-secret — the Dex OIDC client secret (created by the dex module at platform/oauth2-proxy/oidc)
#   cookie-secret — the TF-generated secret above (platform/oauth2-proxy/cookie)
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "external_secret" {
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
          data = {
            "client-id"     = var.oidc_client_id
            "client-secret" = "{{ .clientSecret }}"
            "cookie-secret" = "{{ .cookieSecret }}"
          }
        }
      }
      data = [
        {
          secretKey = "clientSecret"
          remoteRef = { key = var.client_secret_name, property = var.client_secret_key }
        },
        {
          secretKey = "cookieSecret"
          remoteRef = { key = aws_secretsmanager_secret.cookie[0].name, property = "cookie-secret" }
        },
      ]
    }
  }

  depends_on = [aws_secretsmanager_secret_version.cookie]
}

# ---------------------------------------------------------------------------
# oauth2-proxy (oauth2-proxy/oauth2-proxy chart) — auth proxy in front of Backstage (#202)
# ---------------------------------------------------------------------------

resource "helm_release" "oauth2_proxy" {
  count            = local.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false # the backstage module owns the namespace
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = false
  cleanup_on_fail  = false
  replace          = true

  values = [yamlencode(local.values)]

  depends_on = [kubernetes_manifest.external_secret]
}
