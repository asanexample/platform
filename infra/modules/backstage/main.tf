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

      # The chart overrides the image CMD, so re-supply the production config chain (both files are baked
      # into our image). Without the --config args the backend would load only the dev app-config.yaml.
      command = ["node", "packages/backend"]
      args    = ["--config", "app-config.yaml", "--config", "app-config.production.yaml"]

      extraEnvVars = [
        { name = "POSTGRES_HOST", value = local.db_host },
        { name = "POSTGRES_PORT", value = "5432" },
        { name = "POSTGRES_USER", valueFrom = { secretKeyRef = { name = local.db_secret, key = local.db_user_key } } },
        { name = "POSTGRES_PASSWORD", valueFrom = { secretKeyRef = { name = local.db_secret, key = local.db_pass_key } } },
      ]

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
  ]
}
