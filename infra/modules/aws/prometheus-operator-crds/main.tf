locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# Prometheus Operator CRDs (ServiceMonitor, PodMonitor, PrometheusRule, ...)
# ---------------------------------------------------------------------------
# Installed EARLY, before any workload that ships a ServiceMonitor (keycloak,
# argo-rollouts, the observability charts, ...). The kube-prometheus-stack chart
# (the observability unit) otherwise owns these CRDs, but it applies late in the DAG
# — so a from-scratch bootstrap DEADLOCKS: a chart containing a ServiceMonitor fails
# to render ("no matches for kind ServiceMonitor ... ensure CRDs are installed first")
# before the stack that would provide the CRD has run. Owning the CRDs in a dedicated
# early release breaks the cycle; the kube-prometheus-stack releases set
# crds.enabled=false to defer to this one (single owner, no helm ownership conflict).
resource "helm_release" "crds" {
  count = local.create ? 1 : 0

  name       = "prometheus-operator-crds"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"
  version    = var.chart_version
  namespace  = "kube-system" # CRDs are cluster-scoped; the release's own metadata lives here
}
