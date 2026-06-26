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
    }

    # The controller does not gate admission and serves no ingress — the bundled dashboard is operator UI we
    # don't expose. The Gateway-API traffic-router plugin (for weighted canary, ADR-056 D4) is added in a later
    # phase alongside the canary wiring, not here.
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
