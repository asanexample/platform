locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# OpenTelemetry Operator — annotation-driven SDK auto-injection (ADR-077 D3).
# Webhook serving cert via cert-manager (present on the cluster). Installs the Instrumentation CRD.
# ---------------------------------------------------------------------------
resource "helm_release" "operator" {
  count = local.create ? 1 : 0

  name       = "opentelemetry-operator"
  repository = var.helm_repository
  chart      = var.helm_chart
  version    = var.helm_chart_version
  namespace  = var.namespace

  timeout = var.helm_timeout
  wait    = true
  atomic  = true

  values = [yamlencode({
    manager = {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
      # Pin the default sidecar collector image (used for OpenTelemetryCollector CRs, not the SDK inject).
      collectorImage = {
        repository = "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s"
      }
    }
    # Webhook serving cert from cert-manager (ADR-018 — present cluster-wide).
    admissionWebhooks = {
      certManager = { enabled = true }
    }
  })]
}

# ---------------------------------------------------------------------------
# Platform Instrumentation CR — the platform-injected OTLP endpoint + SDK config (ADR-077 D2).
# Delivered as a local Helm chart (not kubernetes_manifest) so it can reference the operator's CRD
# installed in the same apply — the crossplane-module convention. Waits for the operator (its webhook
# validates the CR).
# ---------------------------------------------------------------------------
resource "helm_release" "instrumentation" {
  count = local.create ? 1 : 0

  name      = "platform-instrumentation"
  chart     = "${path.module}/charts/instrumentation"
  namespace = var.namespace

  timeout = var.helm_timeout
  wait    = true

  values = [yamlencode({
    name      = var.instrumentation_name
    namespace = var.namespace
    endpoint  = var.otlp_endpoint
    sampler   = var.sampler
  })]

  depends_on = [helm_release.operator]
}
