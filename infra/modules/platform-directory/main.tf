# The platform identity directory's Postgres (ADR-084 Phase 1). A dedicated PLATFORM-INFRA namespace — NOT a
# tenant environment (no platform.refplat.org/team label), so the tenant Kyverno policies (ECR-only images,
# mandatory probes/limits) don't apply — exactly how keycloak/backstage run their CloudNativePG databases. The
# triage agent connects cross-namespace via Secrets Manager creds; its own namespace keeps EVERY tenant policy
# intact (ADR-084 D13 — the directory stays out of the agent sandbox, no posture change for agents).
#
# Rebuildable projection of Keycloak (D11): no backups configured — it rebuilds from source.

locals {
  create = var.create
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
    spec = {
      instances = var.instances
      storage   = { size = var.storage_size }
      # Keep Karpenter from voluntarily disrupting the node a Postgres instance runs on.
      inheritedMetadata = { annotations = { "karpenter.sh/do-not-disrupt" = "true" } }
      bootstrap         = { initdb = { database = "directory", owner = "directory" } }
      # Set the directory role's password to our deterministic secret (so the SM DSN matches).
      managed = {
        roles = [{
          name           = "directory"
          ensure         = "present"
          login          = true
          passwordSecret = { name = kubernetes_secret_v1.db_role[0].metadata[0].name }
        }]
      }
      enableSuperuserAccess = false
    }
  }
  depends_on = [kubernetes_namespace_v1.this, kubernetes_secret_v1.db_role]
}

# Default-deny posture: allow ONLY the agent's namespace to reach the DB on 5432.
resource "kubernetes_manifest" "db_ingress" {
  count = local.create ? 1 : 0
  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata   = { name = "allow-consumer-to-db", namespace = var.namespace }
    spec = {
      endpointSelector = { matchLabels = { "cnpg.io/cluster" = var.db_cluster_name } }
      ingress = [{
        fromEndpoints = [
          for ns in concat([var.consumer_namespace], var.extra_consumer_namespaces) :
          { matchLabels = { "k8s:io.kubernetes.pod.namespace" = ns } }
        ]
        toPorts = [{ ports = [{ port = "5432", protocol = "TCP" }] }]
      }]
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

# Teardown: force-delete the CNPG Cluster → pods → PVCs before the namespace is deleted, so the namespace
# finalizes cleanly (the pvc-protection finalizer otherwise hangs the destroy). Mirrors the keycloak module.
resource "null_resource" "cnpg_finalizer_cleanup" {
  count = local.create && var.finalizer_clear_script != "" ? 1 : 0
  triggers = {
    script    = var.finalizer_clear_script
    cluster   = var.cluster_name
    region    = var.region
    role_arn  = var.deployer_role_arn
    namespace = var.namespace
    refs      = "cluster.postgresql.cnpg.io pod persistentvolumeclaim"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "bash ${self.triggers.script} --delete ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} ${self.triggers.namespace} ${self.triggers.refs}"
  }
  depends_on = [kubernetes_namespace_v1.this]
}
