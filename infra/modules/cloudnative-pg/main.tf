locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  cnpg_values = {
    replicaCount = var.replica_count
    podLabels    = local.k8s_labels

    # EKS + Cilium overlay (cluster-pool): the EKS managed control plane can't route to overlay pod IPs,
    # so the operator's admission webhook server runs on hostNetwork (node VPC IP). On hostNetwork the
    # webhook port becomes a HOST port — move it off 9443 to avoid colliding with kyverno's admission
    # controller (host 9443) and cleanup controller (9444). 9446 is unused by the platform's hostNetwork
    # webhooks. ClusterFirstWithHostNet keeps cluster DNS working for the operator on hostNetwork.
    hostNetwork = var.webhook_host_network
    dnsPolicy   = var.webhook_host_network ? "ClusterFirstWithHostNet" : ""
    webhook = {
      port = var.webhook_host_network ? 9446 : 9443
    }

    # On hostNetwork the operator's metrics server (controller-runtime default :8080) also binds a HOST
    # port, which collides with other node processes/hostNetwork pods on 8080 (the operator crashloops:
    # "listen tcp :8080: bind: address already in use"). We don't scrape CNPG metrics yet and the
    # readiness probe targets the webhook server (not metrics), so disable it (--metrics-bind-address=0).
    # Re-enable on a free host port when wiring CNPG into the observability hub (#102).
    additionalArgs = var.webhook_host_network ? ["--metrics-bind-address=0"] : []
  }
}

resource "helm_release" "cloudnative_pg" {
  count            = local.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true
  replace          = true

  values = [yamlencode(local.cnpg_values)]
}

# ---------------------------------------------------------------------------
# Barman Cloud CNPG-I plugin (backup engine — #1119)
# ---------------------------------------------------------------------------
# The plugin that gives CNPG clusters base-backup + WAL-archiving to S3 (the in-tree barmanObjectStore is
# deprecated in CNPG 1.26+). Delivered as a VENDORED local chart of the upstream release manifest (v0.13.0):
# the manifest ships a CRD (objectstores.barmancloud.cnpg.io) alongside the Deployment/RBAC/Service, and the
# same-namespace CRD+workload install is exactly the case a local chart handles cleanly (mirrors the
# crossplane module). It must live in the operator namespace and needs cert-manager (issues its mTLS cert to
# the operator). Additive — installing the plugin does nothing to existing clusters until they declare
# spec.plugins; the per-cluster ObjectStore + spec.plugins + ScheduledBackup land in the follow-up.
# wait=false: the Deployment only goes Ready after cert-manager issues the cert, so don't block the apply on
# it (verify with `kubectl rollout status deployment/barman-cloud-plugin -n cnpg-system`).
resource "helm_release" "barman_cloud_plugin" {
  count = local.create && var.enable_barman_plugin ? 1 : 0

  name      = "barman-cloud-plugin"
  chart     = "${path.module}/charts/barman-cloud-plugin"
  namespace = var.namespace
  timeout   = var.helm_timeout
  wait      = false

  depends_on = [helm_release.cloudnative_pg]
}

# ---------------------------------------------------------------------------
# CNPG instance metrics (#1119 PR4) — scrape the per-cluster instance metrics endpoint
# ---------------------------------------------------------------------------
# The operator's own metrics stay off (hostNetwork host-port collision — see cnpg_values above); this scrapes
# the per-INSTANCE endpoint (:9187, cnpg_collector_* — backup freshness, WAL archiving, connections, cluster
# health), which is what the backup/health alerts need. One PodMonitor for CNPG instances in ALL namespaces
# (kube-prometheus-stack's podMonitorSelector/namespaceSelector are empty = select all). CNPG serves :9187 on
# every instance regardless of spec.monitoring, so a plain PodMonitor suffices (no per-Cluster change). NOTE:
# a namespace that default-denies ingress to its DB must admit the observability namespace on 9187 (the
# platform-directory module does).
resource "kubernetes_manifest" "instance_pod_monitor" {
  count = local.create && var.enable_pod_monitor ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "cnpg-instances"
      namespace = var.namespace
      labels    = local.k8s_labels
    }
    spec = {
      namespaceSelector   = { any = true }
      selector            = { matchLabels = { "cnpg.io/podRole" = "instance" } }
      podMetricsEndpoints = [{ port = "metrics" }]
    }
  }

  depends_on = [helm_release.cloudnative_pg]
}
