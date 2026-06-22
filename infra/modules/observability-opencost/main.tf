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
