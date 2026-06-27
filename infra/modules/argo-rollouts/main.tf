locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  argo_rollouts_values = {
    # Manage the Rollout/AnalysisTemplate/Experiment CRDs with the release. The CRDs must exist BEFORE the
    # `policy` unit, whose ADR-085 availability policies match the `Rollout` kind (a Kyverno rule naming a kind
    # with no CRD fails to create — Kyverno #7839). The DAG enforces this via the policy unit's dependency.
    installCRDs = true

    controller = {
      replicas  = var.replica_count
      podLabels = local.k8s_labels

      # Gateway-API traffic-router plugin (ADR-056 D4) — drives weighted canary by editing HTTPRoute
      # backendRef weights. The controller downloads the binary at startup, so it must match the NODE arch
      # (Graviton/arm64 here). The bundled ClusterRole already grants the httproutes RBAC the plugin needs.
      # Proven end-to-end on Cilium 1.19 (a real canary split 50/50 and promoted). Harmless until a Rollout
      # opts in via strategy.canary.trafficRouting.plugins."argoproj-labs/gatewayAPI".
      trafficRouterPlugins = var.enable_gateway_api_plugin ? [
        {
          name     = "argoproj-labs/gatewayAPI"
          location = "https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi/releases/download/${var.gateway_api_plugin_version}/gatewayapi-plugin-linux-${var.gateway_api_plugin_arch}"
        }
      ] : []
    }

    # The controller does not gate admission and serves no ingress — the bundled dashboard is operator UI we
    # don't expose.
    dashboard = {
      enabled = false
    }
  }
}

# ---------------------------------------------------------------------------
# Argo Rollouts controller + CRDs (ADR-056) — the progressive-delivery control plane
# ---------------------------------------------------------------------------

resource "helm_release" "argo_rollouts" {
  count = local.create ? 1 : 0

  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true

  wait    = var.helm_wait
  timeout = 600

  values = [yamlencode(local.argo_rollouts_values)]
}
