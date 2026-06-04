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

  # The image's app-config.production.yaml now carries the complete integrations.github (clientId/clientSecret
  # placeholders) + the type-scoped catalog.rules (Phase 2.2 consolidation, asanexample/backstage#3), so the only
  # remaining chart appConfig layer is the OIDC session secret. The App's appId/privateKey are still injected
  # from the secret via github_env.
  enable_k8s = var.create && var.enable_kubernetes_plugin

  # Kubernetes plugin (Phase 2.4a): live cluster view. Injected as an appConfig layer (env-specific cluster
  # endpoints/CA/assume-role belong in the unit, not the image). authProvider=aws uses the pod's EKS Pod
  # Identity creds for THIS cluster; cross-account clusters set assumeRole (the read-only preprod Backstage role).
  kubernetes_app_config = local.enable_k8s ? {
    kubernetes = {
      serviceLocatorMethod = { type = "multiTenant" }
      clusterLocatorMethods = [{
        type = "config"
        clusters = [for c in var.kubernetes_clusters : merge({
          name         = c.name
          url          = c.url
          authProvider = "aws"
          caData       = c.ca_data
          region       = c.region
          # AmazonEKSViewPolicy doesn't grant the aggregated metrics.k8s.io API, so the optional pod-metrics
          # lookup 403s and shows a spurious "problem retrieving objects" warning. Skip it (workloads/health
          # still render). Grant metrics RBAC + flip this off later if CPU/memory usage is wanted.
          skipMetricsLookup = true
        }, try(c.assume_role, null) != null && try(c.assume_role, "") != "" ? { assumeRole = c.assume_role } : {})]
      }]
    }
  } : {}

  extra_app_config = merge(local.oidc_app_config, local.kubernetes_app_config)

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
      # No IRSA annotation, ever: AWS access (the 2.4a Kubernetes-plugin reader role) is granted via EKS
      # Pod Identity association (below), not an SA annotation — the platform standard (ADR-047).
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
# Kubernetes plugin AWS access (Phase 2.4a) — read-only, EKS Pod Identity.
# The `backstage` ServiceAccount is bound (Pod Identity, no SA annotation — ADR-047) to a reader role with
# cluster-View access on THIS (platform) cluster, plus permission to assume the cross-account read-only
# Backstage role(s) on the workload cluster(s). All read-only: AmazonEKSViewPolicy excludes Secrets.
# The role uses a name_prefix so the workload-account Backstage role can trust it via an ArnLike pattern.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "k8s_reader_trust" {
  count = local.enable_k8s ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "k8s_reader" {
  count = local.enable_k8s ? 1 : 0

  name_prefix        = "${var.cluster_name}-backstage-"
  assume_role_policy = data.aws_iam_policy_document.k8s_reader_trust[0].json
  tags               = var.tags
}

# Allow assuming the cross-account read-only Backstage role(s) on the workload cluster(s).
resource "aws_iam_role_policy" "k8s_reader_remote" {
  count = local.enable_k8s && length(var.remote_cluster_role_arns) > 0 ? 1 : 0

  name = "remote-cluster-read"
  role = aws_iam_role.k8s_reader[0].id

  # sts:TagSession as well as sts:AssumeRole — the Backstage k8s AWS auth assumes the cross-account role
  # with a tagged session (the target role's trust must also allow TagSession).
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Resource = var.remote_cluster_role_arns }]
  })
}

resource "aws_eks_pod_identity_association" "k8s_reader" {
  count = local.enable_k8s ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "backstage"
  role_arn        = aws_iam_role.k8s_reader[0].arn
  tags            = var.tags
}

# Read-only access on the platform cluster itself (the workload clusters grant their own access entries).
resource "aws_eks_access_entry" "k8s_reader" {
  count = local.enable_k8s ? 1 : 0

  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.k8s_reader[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "k8s_reader" {
  count = local.enable_k8s ? 1 : 0

  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.k8s_reader[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope { type = "cluster" }

  depends_on = [aws_eks_access_entry.k8s_reader]
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
    # Pod Identity must exist before the pod starts, or it gets no AWS creds until a restart.
    aws_eks_pod_identity_association.k8s_reader,
  ]
}
