locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  in_cluster_db = var.database.mode == "in-cluster"

  # in-cluster: CloudNativePG creates the `<cluster>-rw` Service (read-write primary) + the `<cluster>-app`
  # Secret (keys username/password) for the initdb owner role.
  db_host   = local.in_cluster_db ? "${var.db_cluster_name}-rw.${var.namespace}.svc.cluster.local" : var.rds_host
  db_secret = local.in_cluster_db ? "${var.db_cluster_name}-app" : var.rds_secret_name

  admin_k8s_secret = "keycloak-admin"
  admin_secret_sm  = "platform/keycloak/admin"

  # Self-owned ingress (ADR-053/059): Keycloak owns its HTTPRoute so the endpoint is up before keycloak-config
  # configures the realm through it. Host derived from hostname_url; backend is the keycloak Service.
  create_route = local.create && var.create_route
  route_host   = replace(replace(var.hostname_url, "https://", ""), "http://", "")

  # ---------------------------------------------------------------------------
  # Keycloak env (KC 26: production `start`, behind a TLS-terminating proxy).
  # extraEnv is a templated YAML *string* in the chart. Admin bootstrap + proxy/hostname go here so we use
  # Keycloak's stable env interface rather than the chart's (older) proxy abstraction.
  # ---------------------------------------------------------------------------
  extra_env = <<-EOT
    - name: KC_PROXY_HEADERS
      value: "xforwarded"
    - name: KC_HOSTNAME
      value: "${var.hostname_url}"
    - name: KC_BOOTSTRAP_ADMIN_USERNAME
      valueFrom:
        secretKeyRef:
          name: ${local.admin_k8s_secret}
          key: username
    - name: KC_BOOTSTRAP_ADMIN_PASSWORD
      valueFrom:
        secretKeyRef:
          name: ${local.admin_k8s_secret}
          key: password
  EOT

  keycloak_values = {
    # Stable Service name ("keycloak") for the gateway-config route backend.
    fullnameOverride = var.helm_release_name
    replicas         = var.replica_count

    image = merge(
      { repository = var.image_repository, pullPolicy = "IfNotPresent" },
      var.image_tag != "" ? { tag = var.image_tag } : {},
    )

    serviceAccount = { create = true, name = var.helm_release_name }

    # The official image's ENTRYPOINT is kc.sh with no default subcommand, so we must pass `start`
    # (production mode; auto-builds from the KC_* env on boot) — per the chart README.
    command = ["/opt/keycloak/bin/kc.sh", "start"]

    # Modern context path (clean issuer URLs: https://<host>/realms/...). TLS terminates at the gateway,
    # so Keycloak serves plain HTTP internally (KC_HTTP_ENABLED via extraEnv).
    http  = { relativePath = "/" }
    proxy = { enabled = false } # use KC_PROXY_HEADERS (extraEnv) — the KC 26 interface

    service = { type = "ClusterIP", httpPort = 80 }

    # Hardened (parity with dex/backstage). readOnlyRootFilesystem is omitted — Keycloak needs writable
    # working dirs and it's not required at the standard tier.
    podSecurityContext = {
      fsGroup        = 1000
      runAsNonRoot   = true
      seccompProfile = { type = "RuntimeDefault" }
    }
    securityContext = {
      runAsUser                = 1000
      runAsNonRoot             = true
      allowPrivilegeEscalation = false
      capabilities             = { drop = ["ALL"] }
    }

    # Wait for the database to accept connections before Keycloak starts (avoids crash-loops on first boot).
    dbchecker = { enabled = true }

    database = {
      vendor            = "postgres"
      hostname          = local.db_host
      port              = "5432"
      database          = "keycloak"
      username          = "keycloak"
      existingSecret    = local.db_secret
      existingSecretKey = "password"
    }

    extraEnv = local.extra_env

    resources = var.resources
    podLabels = local.k8s_labels

    # Metrics exposed but no ServiceMonitor yet (observability hub doesn't scrape this cluster — parity with dex).
    metrics        = { enabled = false }
    serviceMonitor = { enabled = false }
  }
}

# ---------------------------------------------------------------------------
# Namespace
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "keycloak" {
  count = local.create ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(local.k8s_labels, {
      "app.kubernetes.io/name"             = "keycloak"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    })
  }
}

# ---------------------------------------------------------------------------
# In-cluster Postgres (CloudNativePG Cluster) — dev DB; RDS is the prod toggle (deferred).
# CNPG auto-creates the <cluster>-rw Service + the <cluster>-app Secret (username/password). Keycloak uses a
# single database, so no managed CREATEDB role is needed (unlike Backstage). Backups deferred to ADR-054.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "db" {
  count = local.create && local.in_cluster_db ? 1 : 0

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = var.db_cluster_name
      namespace = var.namespace
    }
    spec = {
      instances             = var.database.instances
      storage               = { size = var.database.storage_size }
      bootstrap             = { initdb = { database = "keycloak", owner = "keycloak" } }
      enableSuperuserAccess = false
    }
  }

  depends_on = [kubernetes_namespace_v1.keycloak]
}

# ---------------------------------------------------------------------------
# Admin credential — generated here, stored in Secrets Manager (platform/keycloak/admin),
# synced into the keycloak namespace as the K8s Secret keycloak-admin by External Secrets.
# ---------------------------------------------------------------------------

resource "random_password" "admin" {
  count   = local.create ? 1 : 0
  length  = 32
  special = false # alphanumeric — safe across the SM->ESO->env path
}

resource "aws_secretsmanager_secret" "admin" {
  count                   = local.create ? 1 : 0
  name                    = local.admin_secret_sm
  description             = "Keycloak bootstrap admin credentials."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "admin" {
  count     = local.create ? 1 : 0
  secret_id = aws_secretsmanager_secret.admin[0].id
  secret_string = jsonencode({
    username = var.admin_username
    password = random_password.admin[0].result
  })
}

resource "kubernetes_manifest" "admin_external_secret" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.admin_k8s_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.admin_k8s_secret, creationPolicy = "Owner" }
      data = [
        { secretKey = "username", remoteRef = { key = aws_secretsmanager_secret.admin[0].name, property = "username" } },
        { secretKey = "password", remoteRef = { key = aws_secretsmanager_secret.admin[0].name, property = "password" } },
      ]
    }
  }

  depends_on = [kubernetes_namespace_v1.keycloak, aws_secretsmanager_secret_version.admin]
}

# ---------------------------------------------------------------------------
# Keycloak (codecentric/keycloakx chart) — the app-facing OIDC IdP (ADR-053)
# ---------------------------------------------------------------------------

resource "helm_release" "keycloak" {
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

  values = [yamlencode(local.keycloak_values)]

  depends_on = [
    kubernetes_namespace_v1.keycloak,
    kubernetes_manifest.db,
    kubernetes_manifest.admin_external_secret,
  ]
}

# ---------------------------------------------------------------------------
# Ingress — Keycloak owns its HTTPRoute on the shared Gateway (ADR-053/059).
# Created with Keycloak (before keycloak-config) so the realm can be configured through this endpoint. Attaches to
# the foundational `gateway` unit's Gateway via parentRef (cross-namespace; the Gateway allows routes from All).
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "http_route" {
  count = local.create_route ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = var.helm_release_name
      namespace = var.namespace
    }
    spec = {
      parentRefs = [{
        name        = var.gateway_name
        namespace   = var.gateway_namespace
        sectionName = "https"
      }]
      hostnames = [local.route_host]
      rules = [{
        backendRefs = [{
          name = var.helm_release_name
          port = 80
        }]
      }]
    }
  }

  depends_on = [helm_release.keycloak]
}

resource "kubernetes_manifest" "http_redirect_route" {
  count = local.create_route ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${var.helm_release_name}-redirect"
      namespace = var.namespace
    }
    spec = {
      parentRefs = [{
        name        = var.gateway_name
        namespace   = var.gateway_namespace
        sectionName = "http"
      }]
      hostnames = [local.route_host]
      rules = [{
        filters = [{
          type = "RequestRedirect"
          requestRedirect = {
            scheme     = "https"
            statusCode = 301
          }
        }]
      }]
    }
  }

  depends_on = [helm_release.keycloak]
}
