locals {
  create = var.create

  helm_values = {
    # Application observability (RED + traces), not network mode.
    preset = "application"

    # eBPF needs elevated kernel privileges; the observability namespace is already PSA `privileged`.
    privileged = true

    # Expose Beyla's RED + service-graph metrics for Prometheus to scrape (no metrics-generator needed —
    # ADR-077 D5). The ServiceMonitor targets this metrics Service (chart wires its port/path from
    # prometheus_export), so BOTH must be enabled. serviceMonitorSelectorNilUsesHelmValues=false on the
    # platform Prometheus → it's scraped.
    service        = { enabled = true }
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
      # Beyla instruments ~20 processes (eBPF maps + per-process tracers); 512Mi OOMed (exit 137). Nodes
      # have memory headroom (MemoryPressure=False), so this is a container-limit raise, not a node-size issue.
      requests = { cpu = "50m", memory = "256Mi" }
      limits   = { memory = "1Gi" }
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
