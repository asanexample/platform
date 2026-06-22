locals {
  create = var.create

  # ---- OpenTelemetry Collector helm values (trace gateway: OTLP in -> Tempo) ----
  # Deployment-mode gateway: apps send OTLP to this collector's service; it batches and forwards to
  # Tempo's distributor. No AWS identity (in-cluster forward only). The otelcol-k8s distro carries the
  # otlp receiver/exporter + batch + memory_limiter. We override only the traces pipeline + add the Tempo
  # exporter; the chart's default otlp receiver + batch processor are reused via deep-merge. (k8sattributes
  # enrichment + tail-sampling are follow-up enhancements.)
  helm_values = {
    fullnameOverride = var.helm_release_name
    mode             = "deployment"
    replicaCount     = var.high_availability ? 2 : 1

    image   = { repository = "otel/opentelemetry-collector-k8s" }
    command = { name = "otelcol-k8s" }

    serviceAccount = { create = true, name = var.helm_release_name }

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }

    config = {
      exporters = {
        "otlp/tempo" = {
          endpoint = var.tempo_otlp_endpoint
          tls      = { insecure = true } # in-cluster plaintext to the Tempo distributor
        }
      }
      processors = {
        # memory_limiter must run first; batch coalesces spans before export.
        memory_limiter = {
          check_interval         = "5s"
          limit_percentage       = 80
          spike_limit_percentage = 25
        }
      }
      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "batch"]
            exporters  = ["otlp/tempo"]
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Helm release — open-telemetry/opentelemetry-collector (trace gateway)
# ---------------------------------------------------------------------------

resource "helm_release" "otel_collector" {
  count = local.create ? 1 : 0

  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false # the observability module owns the namespace (PSA label)
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [yamlencode(local.helm_values)]
}
