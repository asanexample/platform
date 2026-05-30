locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123).
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  falco_values = {
    # CO-RE eBPF probe — no kernel module/driver build; works on the AL2023 6.x nodes and runs
    # alongside Cilium's eBPF (different hooks). The DaemonSet runs on every node.
    driver = {
      kind = var.driver_kind
    }

    # Structured output so downstream routing (falcosidekick -> SNS/observability) gets clean fields.
    falco = {
      json_output                  = true
      json_include_output_property = true
    }

    # falcosidekick: the alert-routing layer. With no outputs configured it logs to stdout (verifiable
    # now); SNS/Slack/observability outputs are added via var.falcosidekick_config later.
    falcosidekick = {
      enabled = var.enable_falcosidekick
      config  = var.falcosidekick_config
    }

    resources = var.falco_resources

    # Run on every node, including any tainted ones (runtime detection must be cluster-wide).
    tolerations = [{ operator = "Exists" }]

    podLabels = local.k8s_labels
  }
}

# ---------------------------------------------------------------------------
# Falco engine + falcosidekick (community Helm chart)
# ---------------------------------------------------------------------------

resource "helm_release" "falco" {
  count            = local.create ? 1 : 0
  name             = "falco"
  repository       = var.helm_repository
  chart            = "falco"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [yamlencode(local.falco_values)]
}
