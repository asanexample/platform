locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# OpenTelemetry Operator — annotation-driven SDK auto-injection (ADR-077 D3).
# Webhook serving cert via cert-manager (present on the cluster). Installs the Instrumentation CRD.
# ---------------------------------------------------------------------------
resource "helm_release" "operator" {
  count = local.create ? 1 : 0

  name             = "opentelemetry-operator"
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true # its own namespace (no default-deny that would block the webhook)

  timeout = var.helm_timeout
  wait    = true
  atomic  = true

  values = [yamlencode({
    # The EKS-managed control plane cannot dial a webhook on a Cilium OVERLAY pod IP (BYOCNI — the pod CIDR
    # isn't routed to the control-plane ENIs); the apiserver rejects it with "Address is not allowed", so the
    # mutating webhook (minstrumentation.kb.io) is unreachable and NO Instrumentation CR can be admitted. Run
    # the manager on hostNetwork so its webhook endpoint is a VPC-native NODE IP the control plane can reach —
    # the same pattern every other apiserver-facing webhook here uses (Kyverno admission, cert-manager).
    hostNetwork = true
    manager = {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
      # Pin the default sidecar collector image (used for OpenTelemetryCollector CRs, not the SDK inject).
      collectorImage = {
        repository = "ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s"
      }
      # With hostNetwork these bind on the NODE — offset off the chart defaults so they can't collide with
      # another hostNetwork webhook on a shared node (Kyverno admission also serves on 9443).
      ports = {
        webhookPort = 9444
        healthzPort = 8082
      }
    }
    # Webhook serving cert from cert-manager (ADR-018 — present cluster-wide).
    admissionWebhooks = {
      certManager = { enabled = true }
    }
  })]
}

# NOTE: the `Instrumentation` CR (the platform-injected OTLP endpoint + SDK config, ADR-077 D2) is
# **namespace-scoped** — a workload references one in (or cross-ns from) its own namespace. So rather than a
# single central CR here, it is created **per environment namespace by the golden path (P14)** / the
# Crossplane Environment Composition, pointing at the OTel Collector. The reusable CR template lives in
# `charts/instrumentation/` for P14 to deploy. This module delivers the cluster-wide operator (the
# mechanism); P14 delivers the per-namespace endpoint. Apps opt in via
# `instrumentation.opentelemetry.io/inject-<lang>: "<their-namespace>/<name>"`.
