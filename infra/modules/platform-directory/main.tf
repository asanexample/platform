# The platform identity directory's Postgres (ADR-084 Phase 1). A dedicated PLATFORM-INFRA namespace — NOT a
# tenant environment (no platform.refplat.org/team label), so the tenant Kyverno policies (ECR-only images,
# mandatory probes/limits) don't apply — exactly how keycloak/backstage run their CloudNativePG databases. The
# triage agent connects cross-namespace via Secrets Manager creds; its own namespace keeps EVERY tenant policy
# intact (ADR-084 D13 — the directory stays out of the agent sandbox, no posture change for agents).
#
# The identity projection is a rebuildable view of Keycloak (D11) — but this DB also holds the ADR-088
# activation_audit table (durable break-glass governance audit, NOT rebuildable from source), so Barman Cloud
# backups + continuous WAL archiving are enabled when var.enable_backups (#1119). The activation_audit table is
# the thing that must survive a lost PVC.

locals {
  create = var.create

  # Barman Cloud WAL archiver (#1119) — attached to the Cluster only when backups are on. Empty otherwise so
  # the spec.plugins key is absent (no reconcile churn for backup-less consumers).
  backup_spec = var.enable_backups ? {
    plugins = [{
      name          = "barman-cloud.cloudnative-pg.io"
      isWALArchiver = true
      parameters    = { barmanObjectName = "${var.db_cluster_name}-backup" }
    }]
  } : {}

  # Scoped activation-audit Postgres roles (ADR-088 §3.6 least-privilege): the operator writes as
  # `activation_writer` (INSERT-only on activation_audit), Backstage reads as `activation_reader` (SELECT-only)
  # — neither can touch the directory's identity tables. Their connections are published to the SM ids below.
  audit_db_roles = local.create ? {
    "activation_writer" = var.audit_writer_secret_name
    "activation_reader" = var.audit_reader_secret_name
  } : {}
}

resource "kubernetes_namespace_v1" "this" {
  count = local.create ? 1 : 0
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "platform-directory"
      "app.kubernetes.io/managed-by" = "terragrunt"
      team                           = "platform"
      # Platform-infra namespace — deliberately NO platform.refplat.org/team (would make it tenant-policed).
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

# The `directory` owner-role password CNPG sets (managed role), so the agent's connection string is deterministic
# and we never read CNPG's async-generated -app secret (avoids an apply-time race).
resource "random_password" "db" {
  count   = local.create ? 1 : 0
  length  = 32
  special = false # alphanumeric — safe across the SM->ESO->DSN path
}

resource "kubernetes_secret_v1" "db_role" {
  count = local.create ? 1 : 0
  metadata {
    name      = "${var.db_cluster_name}-role"
    namespace = var.namespace
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "directory"
    password = random_password.db[0].result
  }
  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_manifest" "db" {
  count = local.create ? 1 : 0
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata   = { name = var.db_cluster_name, namespace = var.namespace }
    spec = merge({
      instances = var.instances
      storage   = { size = var.storage_size }
      # Keep Karpenter from voluntarily disrupting the node a Postgres instance runs on.
      inheritedMetadata = { annotations = { "karpenter.sh/do-not-disrupt" = "true" } }
      bootstrap         = { initdb = { database = "directory", owner = "directory" } }
      # Set the directory role's password to our deterministic secret (so the SM DSN matches). The scoped
      # activation-audit roles (writer/reader, ADR-088 §3.6 least-privilege) are managed the same way; their
      # table-level grants on activation_audit (no access to the directory's identity tables) are a one-time
      # SQL run as the directory owner (the table is operator-created — see docs/runbooks/audit-db-grants.md).
      managed = {
        roles = concat([{
          name           = "directory"
          ensure         = "present"
          login          = true
          passwordSecret = { name = kubernetes_secret_v1.db_role[0].metadata[0].name }
          }], [for r in keys(local.audit_db_roles) : {
          name           = r
          ensure         = "present"
          login          = true
          passwordSecret = { name = kubernetes_secret_v1.audit_role[r].metadata[0].name }
        }])
      }
      enableSuperuserAccess = false
    }, local.backup_spec)
  }
  depends_on = [kubernetes_namespace_v1.this, kubernetes_secret_v1.db_role, kubernetes_secret_v1.audit_role]
}

# Barman Cloud backups (#1119): the ObjectStore holds the S3 destination + retention; auth is inheritFromIAMRole
# (the cluster's instance SA is bound to a prefix-scoped backup role via Pod Identity — cnpg-backups module).
resource "kubernetes_manifest" "backup_object_store" {
  count = local.create && var.enable_backups ? 1 : 0
  manifest = {
    apiVersion = "barmancloud.cnpg.io/v1"
    kind       = "ObjectStore"
    metadata   = { name = "${var.db_cluster_name}-backup", namespace = var.namespace }
    spec = {
      retentionPolicy = var.backup_retention
      configuration = {
        destinationPath = var.backup_destination_path
        s3Credentials   = { inheritFromIAMRole = true }
        wal             = { compression = "gzip" }
        data            = { compression = "gzip" }
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.this]
}

# Daily base backup (continuous WAL archiving is automatic once the archiver plugin is attached above).
resource "kubernetes_manifest" "scheduled_backup" {
  count = local.create && var.enable_backups ? 1 : 0
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

# Default-deny posture: consumers reach the DB on 5432; the CNPG operator reaches the instance's management
# ports. Selecting the pod with an endpointSelector makes this default-deny for all OTHER ingress, so the
# operator MUST be admitted explicitly — otherwise it times out polling /pg/status and reports "Instance
# Status Extraction Error: HTTP communication issue" and can't roll the instance to inject the backup sidecar.
resource "kubernetes_manifest" "db_ingress" {
  count = local.create ? 1 : 0
  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata   = { name = "allow-consumer-to-db", namespace = var.namespace }
    spec = {
      endpointSelector = { matchLabels = { "cnpg.io/cluster" = var.db_cluster_name } }
      ingress = [
        {
          fromEndpoints = [
            for ns in concat([var.consumer_namespace], var.extra_consumer_namespaces) :
            { matchLabels = { "k8s:io.kubernetes.pod.namespace" = ns } }
          ]
          toPorts = [{ ports = [{ port = "5432", protocol = "TCP" }] }]
        },
        {
          # The CNPG operator + Barman plugin (cnpg-system) manage the instance: status (8000, the operator
          # polls /pg/status), metrics (9187), and postgres (5432, operator-side management). #1119.
          fromEndpoints = [{ matchLabels = { "k8s:io.kubernetes.pod.namespace" = "cnpg-system" } }]
          toPorts = [{ ports = [
            { port = "8000", protocol = "TCP" },
            { port = "9187", protocol = "TCP" },
            { port = "5432", protocol = "TCP" },
          ] }]
        },
      ]
    }
  }
  depends_on = [kubernetes_namespace_v1.this]
}

# Publish the connection string to Secrets Manager; the agent's ExternalSecret reads it as DATABASE_URL.
resource "aws_secretsmanager_secret" "db" {
  count                   = local.create ? 1 : 0
  name                    = var.db_secret_name
  description             = "Platform identity directory Postgres connection string (ADR-084 Phase 1)."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  count     = local.create ? 1 : 0
  secret_id = aws_secretsmanager_secret.db[0].id
  secret_string = jsonencode({
    uri = "postgresql://directory:${random_password.db[0].result}@${var.db_cluster_name}-rw.${var.namespace}.svc.cluster.local:5432/directory"
  })
}

# ---------------------------------------------------------------------------
# Scoped activation-audit roles (ADR-088 §3.6 least-privilege) — writer (operator) + reader (Backstage).
# ---------------------------------------------------------------------------

resource "random_password" "audit_role" {
  for_each = local.audit_db_roles
  length   = 32
  special  = false # alphanumeric — safe across the SM->ESO->DSN path
}

resource "kubernetes_secret_v1" "audit_role" {
  for_each = local.audit_db_roles
  metadata {
    name      = "${var.db_cluster_name}-${replace(each.key, "_", "-")}"
    namespace = var.namespace
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = each.key
    password = random_password.audit_role[each.key].result
  }
  depends_on = [kubernetes_namespace_v1.this]
}

resource "aws_secretsmanager_secret" "audit_role" {
  for_each                = local.audit_db_roles
  name                    = each.value
  description             = "Scoped activation-audit Postgres connection (${each.key}) — ADR-088 §3.6 least-privilege."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "audit_role" {
  for_each  = local.audit_db_roles
  secret_id = aws_secretsmanager_secret.audit_role[each.key].id
  secret_string = jsonencode({
    uri = "postgresql://${each.key}:${random_password.audit_role[each.key].result}@${var.db_cluster_name}-rw.${var.namespace}.svc.cluster.local:5432/directory"
  })
}

# Teardown: force-delete the CNPG Cluster → pods → PVCs before the namespace is deleted, so the namespace
# finalizes cleanly (the pvc-protection finalizer otherwise hangs the destroy). Mirrors the keycloak module.
#
# The script path is resolved at RUN TIME via `git rev-parse --show-toplevel`, not baked into `triggers` as
# an absolute path — a worktree's checkout lives at a different absolute path than the main checkout, which
# would otherwise make a worktree apply look like a changed trigger and force a replace (firing this
# `when = destroy` provisioner outside of an actual teardown).
resource "null_resource" "cnpg_finalizer_cleanup" {
  count = local.create && var.finalizer_clear_script != "" ? 1 : 0
  triggers = {
    cluster   = var.cluster_name
    region    = var.region
    role_arn  = var.deployer_role_arn
    namespace = var.namespace
    refs      = "cluster.postgresql.cnpg.io pod persistentvolumeclaim"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "bash \"$(git rev-parse --show-toplevel)/scripts/k8s-finalizer-clear.sh\" --delete ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} ${self.triggers.namespace} ${self.triggers.refs}"
  }
  depends_on = [kubernetes_namespace_v1.this]

  # The `script` key is gone from `triggers` (see above) — pin its old value via ignore_changes so
  # existing state (which still has it) doesn't see that as a removed key and force a replace, which
  # would fire the destroy provisioner for real on a live cluster (verified: removing a `triggers` key
  # always forces replacement). A genuine change to cluster/region/role_arn/namespace/refs still
  # replaces normally.
  lifecycle {
    ignore_changes = [triggers["script"]]
  }
}
