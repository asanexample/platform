locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  # The SAML connector's ACS == the OIDC issuer's /callback. The Identity Center SAML app's
  # ACS URL and audience must both equal this (see docs/runbooks/dex-sso.md).
  saml_redirect_uri = "${var.dex_issuer}/callback"

  oidc_secret_key = "client-secret"

  clients_by_id = { for c in var.static_clients : c.id => c }

  # ---------------------------------------------------------------------------
  # Dex configuration (rendered by the chart into a ConfigMap; Dex reads `secretEnv`
  # client secrets straight from the environment — no plaintext secret in this config).
  # ---------------------------------------------------------------------------
  dex_config = {
    issuer = var.dex_issuer

    # CRD-backed storage so all replicas share state (stateless HA). The chart's RBAC
    # (rbac.createClusterScoped) lets Dex create + manage its own dex.coreos.com CRDs.
    storage = {
      type   = "kubernetes"
      config = { inCluster = true }
    }

    # Plaintext HTTP — TLS is terminated at the Cilium Gateway (internal NLB). Must match the
    # Service http port (5556) and the gateway-config `sso` route backend port.
    web = { http = "0.0.0.0:5556" }

    # First-party trusted clients: skip the Dex consent screen. No local password DB.
    oauth2           = { skipApprovalScreen = true }
    enablePasswordDB = false

    staticClients = [for c in var.static_clients : {
      id           = c.id
      name         = c.name
      secretEnv    = c.secret_env
      redirectURIs = c.redirect_uris
    }]

    connectors = [{
      type = "saml"
      id   = "aws-sso"
      name = "AWS SSO"
      config = {
        ssoURL             = var.saml_sso_url
        caData             = var.saml_ca_data
        redirectURI        = local.saml_redirect_uri
        entityIssuer       = local.saml_redirect_uri
        usernameAttr       = "email"
        emailAttr          = "email"
        groupsAttr         = "groups"
        nameIDPolicyFormat = "emailAddress"
      }
    }]
  }

  dex_values = {
    replicaCount = var.replica_count

    image = merge(
      { repository = var.image_repository, pullPolicy = "IfNotPresent" },
      var.image_tag != "" ? { tag = var.image_tag } : {},
      var.image_digest != "" ? { digest = var.image_digest } : {},
    )

    https   = { enabled = false }
    service = { type = "ClusterIP", ports = { http = { port = 5556 } } }

    serviceAccount = { create = true, name = "dex" }
    rbac           = { create = true, createClusterScoped = true }

    # Ingress-only policy (restricts inbound to the Dex ports). Egress stays open: an empty
    # egressRules omits the Egress policyType, so Dex keeps DNS + API-server reachability.
    # Tightening egress is a hardening follow-up (ADR-052).
    networkPolicy = { enabled = true }

    # The backstage namespace gets no tenant Kyverno baseline (platform ns), so harden explicitly.
    podSecurityContext = {
      runAsNonRoot   = true
      runAsUser      = 1001
      fsGroup        = 1001
      seccompProfile = { type = "RuntimeDefault" }
    }
    securityContext = {
      allowPrivilegeEscalation = false
      runAsNonRoot             = true
      readOnlyRootFilesystem   = true
      capabilities             = { drop = ["ALL"] }
    }

    # Dex writes its env-substituted config to a temp file at startup, so a read-only root filesystem
    # needs a writable /tmp. emptyDir keeps the hardening (RO rootfs) without a persistent writable layer.
    volumes      = [{ name = "tmp", emptyDir = {} }]
    volumeMounts = [{ name = "tmp", mountPath = "/tmp" }]

    # Inject each client's generated secret (Secrets Manager -> ExternalSecret -> K8s Secret) as the
    # env var its `secretEnv` references.
    envVars = [for c in var.static_clients : {
      name = c.secret_env
      valueFrom = {
        secretKeyRef = { name = "dex-${c.id}-oidc", key = local.oidc_secret_key }
      }
    }]

    config = local.dex_config

    resources = var.resources
    podLabels = local.k8s_labels
  }
}

# ---------------------------------------------------------------------------
# Namespace
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "dex" {
  count = local.create ? 1 : 0

  metadata {
    name   = var.namespace
    labels = merge(local.k8s_labels, { "app.kubernetes.io/name" = "dex" })
  }
}

# ---------------------------------------------------------------------------
# OIDC client secrets — one per static client.
# Generated here, stored in Secrets Manager (platform/<id>/oidc), and synced into the dex
# namespace (and, for backstage, the backstage namespace via that module) by External Secrets.
# ---------------------------------------------------------------------------

resource "random_password" "client" {
  for_each = local.create ? local.clients_by_id : {}

  length  = 40
  special = false # alphanumeric — safe in URLs/headers and across the SM->ESO->env path
}

resource "aws_secretsmanager_secret" "client" {
  for_each = local.create ? local.clients_by_id : {}

  name                    = "platform/${each.key}/oidc"
  description             = "Dex OIDC client secret for ${each.value.name} (shared by Dex's staticClient and the app)."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "client" {
  for_each = local.create ? local.clients_by_id : {}

  secret_id     = aws_secretsmanager_secret.client[each.key].id
  secret_string = jsonencode({ (local.oidc_secret_key) = random_password.client[each.key].result })
}

# ExternalSecret -> K8s Secret dex-<id>-oidc in the dex namespace (consumed by Dex's envVars).
resource "kubernetes_manifest" "client_external_secret" {
  for_each = local.create ? local.clients_by_id : {}

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "dex-${each.key}-oidc"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = "dex-${each.key}-oidc", creationPolicy = "Owner" }
      data = [{
        secretKey = local.oidc_secret_key
        remoteRef = { key = aws_secretsmanager_secret.client[each.key].name, property = local.oidc_secret_key }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.dex, aws_secretsmanager_secret_version.client]
}

# ---------------------------------------------------------------------------
# Dex (dexidp/dex chart) — the centralized SAML->OIDC broker
# ---------------------------------------------------------------------------

resource "helm_release" "dex" {
  count            = local.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = false
  cleanup_on_fail  = false
  replace          = true

  values = [yamlencode(local.dex_values)]

  depends_on = [
    kubernetes_namespace_v1.dex,
    kubernetes_manifest.client_external_secret,
  ]
}
