# ---------------------------------------------------------------------------
# Crossplane metrics (#1422/#1423) — crossplane also runs on THIS cluster (XEnvironment claims actually
# reconcile here, per ADR-048), so it needs its own PodMonitors, not just the hub's. Mirrors the hub
# `observability` module's crossplane_pod_monitor/crossplane_provider_pod_monitor exactly; duplicated
# rather than shared since each observability module authors its own scrape resources locally.
# ---------------------------------------------------------------------------

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

  depends_on = [helm_release.agent]
}

resource "kubernetes_manifest" "crossplane_provider_pod_monitor" {
  count = local.create && var.enable_crossplane_provider_pod_monitor ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "crossplane-providers"
      namespace = var.namespace
      labels    = local.k8s_labels
    }
    spec = {
      namespaceSelector = { matchNames = ["crossplane-system"] }
      selector = {
        matchExpressions = [{ key = "pkg.crossplane.io/provider", operator = "Exists" }]
      }
      podMetricsEndpoints = [{ port = "metrics", path = "/metrics", interval = "30s" }]
    }
  }

  depends_on = [helm_release.agent]
}
