# CloudNativePG backups (#1119, alerting-blindspot epic #1124). The durable off-cluster home for the hub's
# Postgres clusters' base backups + continuous WAL archiving (point-in-time recovery): a hardened shared S3
# bucket with a per-cluster prefix, plus a least-privilege IAM role per cluster (scoped to its prefix) bound
# to the cluster's instance ServiceAccount via EKS Pod Identity (ADR-047). The Barman Cloud plugin's
# ObjectStore authenticates with inheritFromIAMRole, so these are the creds it writes with. This unit is the
# AWS-side foundation; the plugin install + per-cluster Cluster.spec.plugins + ScheduledBackup land next.

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.cnpg_backups
}

# The EKS cluster id for the Pod Identity associations (the hub the CNPG clusters run on).
dependency "eks" {
  config_path                             = "../eks"
  mock_outputs                            = { cluster_id = "mock-cluster" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create = true

  # Deterministic so each cluster's Barman destinationPath (s3://<bucket>/<cluster>) is known when wiring
  # the ObjectStore CRs.
  bucket_name  = "platform-cnpg-backups"
  cluster_name = dependency.eks.outputs.cluster_id

  # The hub's CNPG clusters. Each gets its own prefix + least-privilege role + Pod Identity association.
  # service_account = the CNPG instance SA (defaults to the cluster name).
  clusters = [
    { name = "keycloak-db", namespace = "keycloak", service_account = "keycloak-db" },
    { name = "backstage-db", namespace = "backstage", service_account = "backstage-db" },
    { name = "triage-copilot-db", namespace = "platform-directory", service_account = "triage-copilot-db" },
  ]

  tags = include.base.locals.tags
}
