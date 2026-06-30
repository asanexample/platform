locals {
  create = var.create

  helm_values = {
    # No bundled Prometheus — we point OpenCost at the existing kube-prometheus-stack Prometheus.
    prometheus = {
      internal = { enabled = false }
      external = { enabled = false }
    }

    opencost = {
      # OpenCost queries this Prometheus for node/pod resource usage → cost allocation.
      prometheus = {
        internal = {
          enabled       = true
          serviceName   = var.prometheus_service
          namespaceName = var.prometheus_namespace
          port          = var.prometheus_port
        }
      }
      # Scrape OpenCost's own cost metrics back into Prometheus (serviceMonitorSelectorNilUsesHelmValues=false
      # on the platform Prometheus → all ServiceMonitors are scraped).
      metrics = {
        serviceMonitor = { enabled = true }
      }
      exporter = {
        resources = {
          requests = { cpu = "10m", memory = "55Mi" }
          limits   = { memory = "256Mi" }
        }
      }
      # No AWS creds: OpenCost uses the public AWS pricing API for on-demand node pricing (cluster-cost
      # allocation). Cloud-cost (CUR/Athena) is a separate, heavier follow-on (#102 P11 part 2).
      cloudCost = { enabled = false }
    }
  }
}

resource "helm_release" "opencost" {
  count = local.create ? 1 : 0

  name       = "opencost"
  repository = var.helm_repository
  chart      = var.helm_chart
  version    = var.helm_chart_version
  namespace  = var.namespace

  timeout = var.helm_timeout
  wait    = true
  atomic  = true

  values = [yamlencode(local.helm_values)]
}

# ---------------------------------------------------------------------------
# Cost dashboard (ADR-091 Phase A) — provisioned as code via the Grafana sidecar (label
# grafana_dashboard=1). Per-team / per-environment compute cost from the OpenCost allocation × node
# hourly-cost metrics this module scrapes; team is derived from the environment-namespace prefix. The
# datasource placeholder is filled with the Mimir uid (where these metrics land).
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "cost_dashboard" {
  count = local.create ? 1 : 0

  metadata {
    name        = "cost-dashboard-by-team"
    namespace   = var.namespace
    labels      = merge(var.tags, { grafana_dashboard = "1" })
    annotations = { grafana_folder = "Cost" }
  }

  data = {
    "team-cost.json" = replace(
      file("${path.module}/dashboards/team-cost.json"),
      "__COST_DS_UID__", var.dashboard_datasource_uid
    )
  }
}
