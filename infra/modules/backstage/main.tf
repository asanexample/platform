locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  in_cluster_db = var.database.mode == "in-cluster"

  # Postgres connection. in-cluster: CloudNativePG creates the `<cluster>-rw` Service (read-write primary)
  # and the `<cluster>-app` Secret (owner user/password/dbname). rds: host + a Secrets-Manager-backed
  # Secret (the unit wires an ExternalSecret) supply the creds.
  db_host     = local.in_cluster_db ? "${var.db_cluster_name}-rw.${var.namespace}.svc.cluster.local" : var.rds_host
  db_secret   = local.in_cluster_db ? "${var.db_cluster_name}-app" : var.rds_secret_name
  db_user_key = local.in_cluster_db ? "username" : "username"
  db_pass_key = local.in_cluster_db ? "password" : "password"

  enable_oidc     = var.create && var.enable_oidc
  oidc_k8s_secret = "backstage-oidc"

  session_k8s_secret = "backstage-session"

  # OIDC needs OIDC_CLIENT_SECRET (shared with Dex's staticClient, synced from Secrets Manager by the
  # ExternalSecret below) and a session-signing secret (AUTH_SESSION_SECRET — backstage-only, generated
  # here). The OAuth handshake stores state in a session cookie, so the oidc provider fails with
  # "authentication requires session support" unless auth.session.secret is set. Empty when OIDC disabled.
  oidc_env = local.enable_oidc ? [
    { name = "OIDC_CLIENT_SECRET", valueFrom = { secretKeyRef = { name = local.oidc_k8s_secret, key = var.oidc_secret_key } } },
    { name = "AUTH_SESSION_SECRET", valueFrom = { secretKeyRef = { name = local.session_k8s_secret, key = "session-secret" } } },
  ] : []

  # Injected as an extra app-config layer via the chart's appConfig (rendered to a ConfigMap + appended
  # to the --config chain). The ConfigMap holds only the ${ENV} placeholder; the value is in the env var.
  # $${...} escapes HCL interpolation so the literal ${AUTH_SESSION_SECRET} reaches Backstage.
  oidc_app_config = local.enable_oidc ? { auth = { session = { secret = "$${AUTH_SESSION_SECRET}" } } } : {}

  # GitHub App for catalog discovery (Phase 2.2). The read-only App's appId + private key (synced from
  # platform/backstage/github-app by the ExternalSecret below) feed integrations.github.apps in the image's
  # app-config.production.yaml. Empty env when disabled.
  github_enabled    = var.create && var.enable_github_discovery
  github_k8s_secret = "backstage-github-app"
  github_env = local.github_enabled ? [
    { name = "GITHUB_APP_ID", valueFrom = { secretKeyRef = { name = local.github_k8s_secret, key = "appId" } } },
    { name = "GITHUB_APP_PRIVATE_KEY", valueFrom = { secretKeyRef = { name = local.github_k8s_secret, key = "privateKey" } } },
  ] : []

  # Provide the COMPLETE integrations.github via the chart appConfig layer (loaded last, so its array replaces
  # the image's app-config.production.yaml entry). appId/privateKey come from the App secret (env). Backstage's
  # integration schema ALSO requires clientId/clientSecret, but installation-token catalog discovery never uses
  # them (they're OAuth/sign-in creds) — so they're placeholders. This App is discovery-only, not a sign-in
  # provider; we deliberately don't mint a real, unused OAuth client secret. (Fold these into the image's
  # app-config on the next backstage image build so this override becomes redundant.)
  github_app_config = local.github_enabled ? {
    integrations = {
      github = [{
        host = "github.com"
        apps = [{
          appId        = "$${GITHUB_APP_ID}"
          privateKey   = "$${GITHUB_APP_PRIVATE_KEY}"
          clientId     = "discovery-only-unused"
          clientSecret = "discovery-only-unused"
        }]
      }]
    }
  } : {}

  # Combined extra app-config layer (chart appConfig -> ConfigMap -> appended to the --config chain).
  extra_app_config = merge(local.oidc_app_config, local.github_app_config)

  backstage_values = {
    # We bring our own Postgres (CNPG or RDS) — never the chart's bundled bitnami Postgres.
    postgresql = { enabled = false }
    # Ingress is the Cilium Gateway (gateway-config HTTPRoute), not a K8s Ingress.
    ingress = { enabled = false }

    service = {
      type  = "ClusterIP"
      ports = { backend = 7007 }
    }

    serviceAccount = {
      create = true
      name   = "backstage"
      # No IRSA annotation: 2.0 needs no AWS access (guest auth, DB only). Pod Identity for the
      # Identity Store / catalog projection is added in 2.1/2.3.
    }

    # The chart's NetworkPolicy restricts ingress to the backstage pod (egress stays open for now —
    # the portal must reach the DB, GitHub and AWS; a tightened egress policy is a 2.1 hardening step).
    networkPolicy = { enabled = true }

    backstage = {
      image = {
        registry   = var.image_registry
        repository = var.image_repository
        tag        = var.image_tag
        pullPolicy = "IfNotPresent"
      }

      replicas       = var.replica_count
      containerPorts = { backend = 7007 }

      # Split-horizon: resolve the OIDC issuer host to the in-cluster gateway so backend<->Dex
      # traffic never leaves the cluster (see var.host_aliases). Empty list = no aliases.
      hostAliases = var.host_aliases

      # The chart overrides the image CMD, so re-supply the production config chain (both files are baked
      # into our image). Without the --config args the backend would load only the dev app-config.yaml.
      command = ["node", "packages/backend"]
      args    = ["--config", "app-config.yaml", "--config", "app-config.production.yaml"]

      extraEnvVars = concat([
        { name = "POSTGRES_HOST", value = local.db_host },
        { name = "POSTGRES_PORT", value = "5432" },
        { name = "POSTGRES_USER", valueFrom = { secretKeyRef = { name = local.db_secret, key = local.db_user_key } } },
        { name = "POSTGRES_PASSWORD", valueFrom = { secretKeyRef = { name = local.db_secret, key = local.db_pass_key } } },
      ], local.oidc_env, local.github_env)

      # Extra app-config layer (chart renders it to a ConfigMap and appends --config): OIDC session
      # support (auth.session.secret) + the complete integrations.github (Phase 2.2). Empty {} when both off.
      appConfig = local.extra_app_config

      resources = var.resources

      # Hardening (the backstage namespace gets no tenant Kyverno mutate baseline — ADR-051 security).
      # readOnlyRootFilesystem is left false: the Backstage backend writes to a working dir (techdocs/
      # scaffolder); locking it down needs writable emptyDir mounts — a 2.1 hardening step.
      podSecurityContext = {
        runAsNonRoot   = true
        runAsUser      = 1000
        fsGroup        = 1000
        seccompProfile = { type = "RuntimeDefault" }
      }
      containerSecurityContext = {
        allowPrivilegeEscalation = false
        runAsNonRoot             = true
        capabilities             = { drop = ["ALL"] }
      }

      podLabels = local.k8s_labels
    }
  }
}

# ---------------------------------------------------------------------------
# Namespace (owns the DB Cluster + the helm release)
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "backstage" {
  count = local.create ? 1 : 0

  metadata {
    name   = var.namespace
    labels = merge(local.k8s_labels, { "app.kubernetes.io/name" = "backstage" })
  }
}

# ---------------------------------------------------------------------------
# In-cluster Postgres (CloudNativePG Cluster) — dev DB; RDS is the prod toggle
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
      # imageName omitted → CNPG uses its default operand Postgres image for the operator version.
      instances             = var.database.instances
      storage               = { size = var.database.storage_size }
      bootstrap             = { initdb = { database = "backstage", owner = "backstage" } }
      enableSuperuserAccess = false

      # Backstage creates a separate database per plugin (backstage_plugin_*) at startup, so its app role
      # needs CREATEDB. CNPG's initdb owner doesn't get it by default and we keep superuser access off, so
      # grant it declaratively via a managed role (reconciled onto the running cluster — no recreate, no
      # imperative `ALTER ROLE`). passwordSecret points at CNPG's generated app secret so the password is
      # left as-is.
      managed = {
        roles = [{
          name           = "backstage"
          ensure         = "present"
          login          = true
          createdb       = true
          passwordSecret = { name = "${var.db_cluster_name}-app" }
        }]
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# OIDC client secret (Phase 2.1) — synced from Secrets Manager by External Secrets.
# The secret itself is created by the dex module (platform/backstage/oidc); here we just
# project it into the backstage namespace as the K8s Secret backstage-oidc.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "oidc_external_secret" {
  count = local.enable_oidc ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.oidc_k8s_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.oidc_k8s_secret, creationPolicy = "Owner" }
      data = [{
        secretKey = var.oidc_secret_key
        remoteRef = { key = var.oidc_secret_name, property = var.oidc_secret_key }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# GitHub App credential (Phase 2.2) — read-only App for catalog discovery.
# Created manually in Secrets Manager (the private key is GitHub-generated); see
# docs/runbooks/backstage-github-app.md. JSON keys: appId, privateKey.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "github_app_external_secret" {
  count = local.github_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.github_k8s_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.github_k8s_secret, creationPolicy = "Owner" }
      data = [
        { secretKey = "appId", remoteRef = { key = var.github_app_secret_name, property = "appId" } },
        { secretKey = "privateKey", remoteRef = { key = var.github_app_secret_name, property = "privateKey" } },
      ]
    }
  }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# Session-signing secret (Phase 2.1) — backstage-only, generated here (not shared, so no
# Secrets Manager round-trip needed). Backed AUTH_SESSION_SECRET; stable across applies.
# ---------------------------------------------------------------------------

resource "random_password" "session" {
  count   = local.enable_oidc ? 1 : 0
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "session" {
  count = local.enable_oidc ? 1 : 0

  metadata {
    name      = local.session_k8s_secret
    namespace = var.namespace
  }
  data = { "session-secret" = random_password.session[0].result }

  depends_on = [kubernetes_namespace_v1.backstage]
}

# ---------------------------------------------------------------------------
# Backstage (official chart, our image)
# ---------------------------------------------------------------------------

resource "helm_release" "backstage" {
  count            = local.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false # the namespace resource above owns it
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = false # don't auto-rollback: the DB Cluster provisions async; verify health out of band
  cleanup_on_fail  = false
  replace          = true

  values = [yamlencode(local.backstage_values)]

  depends_on = [
    kubernetes_namespace_v1.backstage,
    kubernetes_manifest.db,
    kubernetes_manifest.oidc_external_secret,
    kubernetes_secret_v1.session,
    kubernetes_manifest.github_app_external_secret,
  ]
}
