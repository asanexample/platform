locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123), matching the other observability modules.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }
}

# ---------------------------------------------------------------------------
# Sloth controller — watches PrometheusServiceLevel CRs and generates the SLI recording rules + multi-window
# burn-rate alert PrometheusRules. The hub Prometheus discovers those rules (ruleSelectorNilUsesHelmValues=
# false); alerts route via the P4 Alertmanager by severity. The chart bundles the CRD (crds/), so helm_release
# installs it automatically. No webhook → the observability ns default-deny-ingress is fine.
# ---------------------------------------------------------------------------

resource "helm_release" "sloth" {
  count = local.create && var.slo_engine == "sloth" ? 1 : 0

  name             = "sloth"
  repository       = var.helm_repository
  chart            = "sloth"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true
}

# ---------------------------------------------------------------------------
# SLO definitions (PrometheusServiceLevel CRs) — deployed via a local chart so the CRs don't need the CRD
# present at plan time (unlike kubernetes_manifest). depends_on the controller so the CRD exists first.
# ---------------------------------------------------------------------------

resource "helm_release" "slos" {
  count = local.create && var.slo_engine == "sloth" && length(var.slos) > 0 ? 1 : 0

  name             = "slos"
  chart            = "${path.module}/charts/slos"
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = false # the CRs apply instantly; the controller generates the rules asynchronously
  cleanup_on_fail  = true

  values = [yamlencode({ namespace = var.namespace, slos = var.slos })]

  depends_on = [helm_release.sloth]
}

# ---------------------------------------------------------------------------
# Sloth SLO dashboard (grafana.com 14643) — provisioned as code via the observability Grafana sidecar
# (label grafana_dashboard=1). Datasource picker is scoped to our Mimir datasources; the placeholder is
# filled with the configured uid (the hub Mimir, where the SLI/burn-rate recording rules land).
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "slo_dashboard" {
  count = local.create ? 1 : 0

  metadata {
    name      = "slo-dashboard-sloth-high-level"
    namespace = var.namespace
    labels    = merge(local.k8s_labels, { grafana_dashboard = "1" })
    annotations = {
      grafana_folder = "SLOs"
    }
  }

  data = {
    "sloth-slos-high-level.json" = replace(
      file("${path.module}/dashboards/sloth-slos-high-level.json"),
      "__SLO_DS_UID__", var.slo_dashboard_datasource_uid
    )
  }
}
