locals {
  create = var.create

  helm_values = {
    # Metrics: watches PolicyReport/ClusterPolicyReport (Kyverno's ADR-014 admission engine, both
    # validate/mutate + verifyImages/verifyAttestations) and exposes policy_report_result /
    # cluster_policy_report_result series. "detailed" mode carries the full label set (namespace, policy,
    # rule, kind, name, status, severity, category, source) — the dashboards below key off it.
    metrics = {
      enabled = true
      mode    = "detailed"
    }

    # Scraped by the local Prometheus/prometheus-agent (serviceMonitorSelectorNilUsesHelmValues=false on
    # both, #102 P1/P10) and remote_written to the hub Mimir under this cluster's tenant — no external
    # wiring needed (unlike OpenCost, policy-reporter doesn't query Prometheus itself, it only emits).
    # NB: `monitoring.enabled` is a separate top-level gate the chart requires alongside the nested
    # serviceMonitor/grafana toggles below — every monitoring template checks it first.
    monitoring = {
      enabled = true

      serviceMonitor = { enabled = true }

      # Bundled Grafana dashboards (Overview / PolicyReport details / ClusterPolicyReport details) via the
      # same sidecar ConfigMap convention this repo already uses (grafana_dashboard=1 label,
      # grafana_folder annotation) — ship them only where Grafana runs (the hub); a spoke just emits
      # metrics for the hub's federated Mimir datasource to render.
      grafana = {
        dashboards = {
          enabled = var.create_dashboards
          # Every dashboard gets a $cluster filter (label_values(..., cluster)) — externalLabels.cluster
          # (ADR-043/044) is on every series regardless of source, so this works out of the box; matches
          # the house dashboard convention (#151).
          multicluster = {
            enabled = true
            label   = "cluster"
          }
        }
      }
    }

    resources = {
      requests = { cpu = "10m", memory = "64Mi" }
      limits   = { memory = "256Mi" }
    }
  }
}

resource "helm_release" "policy_reporter" {
  count = local.create ? 1 : 0

  name       = "policy-reporter"
  repository = var.helm_repository
  chart      = var.helm_chart
  version    = var.helm_chart_version
  namespace  = var.namespace

  timeout = var.helm_timeout
  wait    = true
  atomic  = true

  values = [yamlencode(local.helm_values)]
}
