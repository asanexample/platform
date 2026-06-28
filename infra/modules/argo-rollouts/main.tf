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

      # Export controller metrics (rollout_info, rollout_phase, analysis run results, …) + a ServiceMonitor so the
      # cluster's Prometheus/agent scrapes them into Mimir (serviceMonitorSelectorNilUsesHelmValues=false ⇒ all
      # SMs picked up, no selector label needed). Powers the Argo Rollouts Grafana dashboard — the visibility
      # for canary weight progression / analysis pass-fail / rollout health (ADR-056).
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true }
      }
    }

    # The bundled Argo Rollouts WEB UI (a separate Deployment + Service) — the live operator view of rollouts:
    # canary step/weight progression, AnalysisRun results, and promote/abort controls. Exposed internally via an
    # HTTPRoute on the shared Gateway (gateway-config `rollouts` route, Tailscale-only). ⚠️ The UI has NO built-in
    # auth and its ServiceAccount can promote/abort rollouts — same internal-trust model as Hubble; harden with an
    # OIDC proxy or a read-only SA if it ever needs wider exposure.
    dashboard = {
      enabled = var.enable_dashboard
      # The dashboard is namespace-scoped and HANGS on an empty default namespace (no initial watch response →
      # the SPA spins forever). Default it to a namespace that has rollouts so it renders; the UI's namespace
      # switcher still reaches the others (it discovers them cluster-wide via its ClusterRole). Empty = the pod's
      # own ns (argo-rollouts) — only safe on a cluster that actually has rollouts there.
      extraArgs = var.dashboard_default_namespace != "" ? ["--namespace=${var.dashboard_default_namespace}"] : []
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
