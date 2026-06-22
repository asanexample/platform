locals {
  create = var.create

  helm_values = {
    # Application observability (RED + traces), not network mode.
    preset = "application"

    # eBPF needs elevated kernel privileges; the observability namespace is already PSA `privileged`.
    privileged = true

    # Expose Beyla's RED + service-graph metrics for Prometheus to scrape (no metrics-generator needed —
    # ADR-077 D5). serviceMonitorSelectorNilUsesHelmValues=false on the platform Prometheus → it's scraped.
    serviceMonitor = { enabled = true }

    config = {
      data = {
        # Tag spans/metrics with Kubernetes metadata (namespace/pod/deployment).
        attributes = {
          kubernetes = { enable = true }
        }
        # Dogfood scope: instrument the human-facing platform HTTP services (real traffic → non-empty
        # service graph immediately). Broadened per-tenant at P10.
        discovery = {
          instrument = [
            { k8s_namespace = var.instrument_namespaces },
          ]
        }
        # Traces → the OpenTelemetry Collector gateway (P3b) → Tempo.
        otel_traces_export = {
          endpoint = var.otel_traces_endpoint
          protocol = "grpc"
        }
        # RED + service-graph metrics on Beyla's own Prometheus endpoint (scraped via the ServiceMonitor).
        prometheus_export = {
          port     = 9090
          path     = "/metrics"
          features = ["application", "application_service_graph"]
        }
      }
    }

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "512Mi" }
    }
  }
}

resource "helm_release" "beyla" {
  count = local.create ? 1 : 0

  name       = "beyla"
  repository = var.helm_repository
  chart      = var.helm_chart
  version    = var.helm_chart_version
  namespace  = var.namespace

  timeout = var.helm_timeout
  # DaemonSet on cost-tight nodes: don't let a momentary unschedulable pod roll back the release
  # (same lesson as the Alloy DaemonSet).
  wait   = false
  atomic = false

  values = [yamlencode(local.helm_values)]
}
