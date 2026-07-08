locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  in_cluster_db = var.database.mode == "in-cluster"

  # Barman Cloud backups (#1119) for the in-cluster DB. backup_spec is merged into the Cluster spec so the
  # WAL-archiver plugin is absent (no reconcile churn) unless backups are on.
  db_backups_enabled = local.in_cluster_db && var.database.enable_backups
  backup_spec = local.db_backups_enabled ? {
    plugins = [{
      name          = "barman-cloud.cloudnative-pg.io"
      isWALArchiver = true
      parameters    = { barmanObjectName = "${var.db_cluster_name}-backup" }
    }]
  } : {}

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
    # Expose Micrometer metrics + health on the management port (9000) so the hub Prometheus can scrape
    # Keycloak (alerting P1, #1121 — SSO is the IdP for ArgoCD/Grafana/Backstage/the agent). KC_HEALTH is
    # required alongside metrics for the management interface to serve them.
    - name: KC_METRICS_ENABLED
      value: "true"
    - name: KC_HEALTH_ENABLED
      value: "true"
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

    # Scrape Keycloak's Micrometer metrics into the hub Prometheus (alerting P1, #1121). The hub Prometheus
    # DOES scrape this (platform) cluster — the old "hub doesn't scrape this cluster / parity with dex" note
    # was stale (Dex is retired, ADR-053/059). The chart exposes the management port + a ServiceMonitor.
    metrics        = { enabled = true }
    serviceMonitor = { enabled = true }
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
    spec = merge({
      instances = var.database.instances
      storage   = { size = var.database.storage_size }

      # Propagate the Karpenter do-not-disrupt annotation to the CNPG-managed instance Pods so Karpenter
      # won't voluntarily disrupt (consolidate/drift/expire) the node a Postgres primary/replica runs on.
      # inheritedMetadata is applied by CNPG to all Cluster-owned objects, the instance Pods included.
      inheritedMetadata = {
        annotations = { "karpenter.sh/do-not-disrupt" = "true" }
      }

      bootstrap             = { initdb = { database = "keycloak", owner = "keycloak" } }
      enableSuperuserAccess = false
    }, local.backup_spec)
  }

  depends_on = [kubernetes_namespace_v1.keycloak]
}

# Barman Cloud backups (#1119): ObjectStore (S3 destination + retention; auth = inheritFromIAMRole via the
# cluster's Pod-Identity backup role) + a daily ScheduledBackup. encryption AES256 → barman sends the SSE
# header the org enforce-encryption SCP requires. destination_path is the bucket ROOT (barman appends the
# server name = cluster). Keycloak's DB is the platform's identity source of truth — the highest-stakes to back up.
resource "kubernetes_manifest" "backup_object_store" {
  count = local.create && local.db_backups_enabled ? 1 : 0
  manifest = {
    apiVersion = "barmancloud.cnpg.io/v1"
    kind       = "ObjectStore"
    metadata   = { name = "${var.db_cluster_name}-backup", namespace = var.namespace }
    spec = {
      retentionPolicy = var.database.retention
      configuration = {
        destinationPath = var.database.destination_path
        s3Credentials   = { inheritFromIAMRole = true }
        wal             = { compression = "gzip", encryption = "AES256" }
        data            = { compression = "gzip", encryption = "AES256" }
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.keycloak]
}

resource "kubernetes_manifest" "scheduled_backup" {
  count = local.create && local.db_backups_enabled ? 1 : 0
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "ScheduledBackup"
    metadata   = { name = "${var.db_cluster_name}-daily", namespace = var.namespace }
    spec = {
      schedule             = var.backup_schedule
      backupOwnerReference = "self"
      cluster              = { name = var.db_cluster_name }
      method               = "plugin"
      pluginConfiguration  = { name = "barman-cloud.cloudnative-pg.io" }
    }
  }
  depends_on = [kubernetes_manifest.db, kubernetes_manifest.backup_object_store]
}

# ---------------------------------------------------------------------------
# Teardown: drain the CNPG database before the namespace is deleted.
# ---------------------------------------------------------------------------
# The namespace delete (kubernetes_namespace_v1.keycloak, destroyed last) finalizes only once every object in
# it is gone — but the CNPG database leaves a PersistentVolumeClaim stuck Terminating (the `kubernetes.io/
# pvc-protection` finalizer is held while its instance pod lingers; under teardown node pressure that pod gets
# stuck Completed and is never reaped). So the namespace hangs ~5m and the destroy times out ("context deadline
# exceeded") — the observed platform/keycloak teardown failure. This runs FIRST on teardown (depends_on the
# namespace => reverse-order destroy) and force-deletes the CNPG Cluster (clearing its finalizer so the operator
# stops reconciling instances), then the pods (releasing pvc-protection), then the PVCs — so the namespace
# finalizes cleanly. Best-effort + self-authenticating (scripts/k8s-finalizer-clear.sh); a missing kind no-ops.
#
# The script path is resolved at RUN TIME via `git rev-parse --show-toplevel`, not baked into `triggers` as
# an absolute path — a worktree's checkout lives at a different absolute path than the main checkout, which
# would otherwise make a worktree apply look like a changed trigger and force a replace (firing this
# `when = destroy` provisioner outside of an actual teardown).
resource "null_resource" "cnpg_finalizer_cleanup" {
  count = local.create && local.in_cluster_db && var.finalizer_clear_script != "" ? 1 : 0

  triggers = {
    cluster   = var.cluster_name
    region    = var.region
    role_arn  = var.deployer_role_arn
    namespace = var.namespace
    # Order matters: the Cluster first (stops the operator recreating instances), then pods (frees
    # pvc-protection), then the PVCs. Kind-only refs => the script enumerates every object of that kind.
    refs = "cluster.postgresql.cnpg.io pod persistentvolumeclaim"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash \"$(git rev-parse --show-toplevel)/scripts/k8s-finalizer-clear.sh\" --delete ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} ${self.triggers.namespace} ${self.triggers.refs}"
  }

  depends_on = [kubernetes_namespace_v1.keycloak]

  # The `script` key is gone from `triggers` (see above) — pin its old value via ignore_changes so
  # existing state (which still has it) doesn't see that as a removed key and force a replace, which
  # would fire the destroy provisioner for real on a live cluster (verified: removing a `triggers` key
  # always forces replacement). A genuine change to cluster/region/role_arn/namespace/refs still
  # replaces normally.
  lifecycle {
    ignore_changes = [triggers["script"]]
  }
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

# Seal the crown-jewel secret (ADR-087): deny GetSecretValue to anyone outside the sealed-reader allow-list — so
# even AdministratorAccess can't read it. Each reader role ARN is expanded to its `:role/` form AND its
# `:sts:…:assumed-role/…/*` session form (aws:PrincipalArn can present either), so a legit reader is never denied.
# The Deny is scoped to GetSecretValue only (PutResourcePolicy stays open → an admin can always unseal/fix it, so a
# bad list is recoverable, never a permanent lockout). Off until var.admin_secret_reader_role_arns is set.
locals {
  seal_admin_secret = local.create && length(var.admin_secret_reader_role_arns) > 0
  admin_reader_arn_patterns = flatten([
    for a in var.admin_secret_reader_role_arns : [
      a,
      "${replace(replace(a, "arn:aws:iam::", "arn:aws:sts::"), ":role/", ":assumed-role/")}/*",
    ]
  ])
}

resource "aws_secretsmanager_secret_policy" "admin" {
  count      = local.seal_admin_secret ? 1 : 0
  secret_arn = aws_secretsmanager_secret.admin[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyReadExceptSealedReaders"
      Effect    = "Deny"
      Principal = "*"
      Action    = "secretsmanager:GetSecretValue"
      Resource  = "*"
      Condition = {
        StringNotLike = { "aws:PrincipalArn" = local.admin_reader_arn_patterns }
      }
    }]
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
          # The keycloakx chart names the HTTP Service <release>-http (not <release>).
          name = "${var.helm_release_name}-http"
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
