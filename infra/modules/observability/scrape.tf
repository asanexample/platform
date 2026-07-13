# ---------------------------------------------------------------------------
# CloudNativePG instance metrics (#1119 PR4)
# ---------------------------------------------------------------------------
# Scrape the per-instance CNPG metrics endpoint (:9187, cnpg_collector_* — backup freshness, WAL archiving,
# cluster health, connections) that the CNPG backup/health alerts need. The operator's own metrics stay off
# (hostNetwork host-port collision). One PodMonitor for cnpg.io/podRole=instance pods in ALL namespaces (this
# stack's podMonitorSelector/namespaceSelector are empty = select all). Lives here (not the cloudnative-pg
# module) because that unit configures only the helm provider; kubernetes_manifest needs the kubernetes
# provider this module has. A namespace that default-denies ingress to its DB must admit observability on 9187
# (platform-directory does). CNPG serves :9187 on every instance, so no per-Cluster spec.monitoring change.
resource "kubernetes_manifest" "cnpg_instance_pod_monitor" {
  count = local.create && var.enable_cnpg_pod_monitor ? 1 : 0

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

  depends_on = [helm_release.kube_prometheus_stack]
}

# Crossplane core-controller metrics (alerting P1, #1121) — lives here (not the crossplane module) for the same
# reason as the CNPG PodMonitor: kubernetes_manifest needs the kubernetes provider this module has, and the
# crossplane module deliberately avoids kubernetes_manifest (plan-time CRD/REST-client problem). The crossplane
# module sets `metrics.enabled` to expose the named `metrics` port; this scrapes it → `up{namespace=
# "crossplane-system"}` (CrossplaneDown) + the core's controller-runtime reconcile metrics (ControllerReconcileErrors).
resource "kubernetes_manifest" "crossplane_pod_monitor" {
  count = local.create && var.enable_crossplane_pod_monitor ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "crossplane"
      namespace = var.namespace
      labels    = local.k8s_labels
    }
    spec = {
      namespaceSelector   = { matchNames = ["crossplane-system"] }
      selector            = { matchLabels = { app = "crossplane" } }
      podMetricsEndpoints = [{ port = "metrics", path = "/metrics", interval = "30s" }]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
