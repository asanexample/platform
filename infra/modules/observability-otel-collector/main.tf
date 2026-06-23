locals {
  create = var.create

  # ---- OpenTelemetry Collector helm values (trace gateway/spoke: OTLP in -> Tempo) ----
  # Deployment-mode gateway: apps send OTLP to this collector's service; it batches and forwards to Tempo.
  # The otelcol-k8s distro carries the otlp receiver/exporter + batch + memory_limiter. We override only the
  # traces pipeline + the Tempo exporter; the chart's default otlp receiver + batch processor are reused via
  # deep-merge. Dual-purpose (#628): HUB exports OTLP/gRPC to the in-cluster Tempo distributor; a SPOKE
  # exports OTLP/HTTP to the hub Tempo edge over the Gateway + stamps cluster via a resource processor.
  exporter_name = var.exporter_use_http ? "otlphttp/tempo" : "otlp/tempo"

  # Both protocols carry the X-Scope-OrgID tenant header (Tempo multitenancy). For a spoke the hub edge
  # overwrites it anyway; for the hub it's the real tenant write.
  tempo_exporter = {
    (local.exporter_name) = {
      endpoint = var.tempo_otlp_endpoint # gRPC: host:port. HTTP: base URL (otlphttp appends /v1/traces).
      headers  = { "X-Scope-OrgID" = var.tenant_id }
      tls      = { insecure = var.exporter_tls_insecure }
    }
  }

  # A resource processor stamps static attributes (e.g. cluster=preprod on a spoke). Omitted when none.
  resource_processor = length(var.resource_attributes) > 0 ? {
    resource = { attributes = [for k, v in var.resource_attributes : { key = k, action = "upsert", value = v }] }
  } : {}

  pipeline_processors = concat(
    ["memory_limiter", "batch"],
    length(var.resource_attributes) > 0 ? ["resource"] : [],
  )

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
      exporters = local.tempo_exporter
      processors = merge({
        # memory_limiter must run first; batch (from the chart) coalesces spans before export.
        memory_limiter = {
          check_interval         = "5s"
          limit_percentage       = 80
          spike_limit_percentage = 25
        }
      }, local.resource_processor)
      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = local.pipeline_processors
            exporters  = [local.exporter_name]
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
