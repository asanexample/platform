locals {
  create  = var.create
  sa_name = var.helm_release_name

  # Sanitize tags for K8s label compliance (RFC 1123), matching the other observability modules.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  # Render external_labels into River syntax (a block-level arg on loki.write). Empty => omitted entirely.
  external_labels_block = length(var.external_labels) > 0 ? "external_labels = { ${join(", ", [for k, v in var.external_labels : "\"${k}\" = \"${v}\""])} }" : ""

  # ---- Alloy River config: tail this node's pod logs -> Loki (tenant _platform) ----
  # DaemonSet + file-tailing is the node-local pattern (each Alloy reads only its own node's
  # /var/log/pods, so no duplicate ingestion). discovery.kubernetes provides pod metadata only
  # (list/watch via the chart's ClusterRole) — logs are read from the host files, so no pods/log RBAC.
  alloy_config = <<-RIVER
    // Discover ONLY this node's pods (DaemonSet: filter on spec.nodeName).
    discovery.kubernetes "pods" {
      role = "pod"
      selectors {
        role  = "pod"
        field = format("spec.nodeName=%s", sys.env("NODE_NAME"))
      }
    }

    // Derive labels + the on-node container log path from pod metadata.
    discovery.relabel "pod_logs" {
      targets = discovery.kubernetes.pods.targets

      rule {
        source_labels = ["__meta_kubernetes_namespace"]
        target_label  = "namespace"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_name"]
        target_label  = "pod"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_container_name"]
        target_label  = "container"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
        target_label  = "app"
      }
      // /var/log/pods/<ns>_<pod>_<uid>/<container>/*.log  — the leading glob matches <ns>_<pod>_.
      rule {
        source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
        separator     = "/"
        action        = "replace"
        replacement   = "/var/log/pods/*$1/*.log"
        target_label  = "__path__"
      }
    }

    local.file_match "pod_logs" {
      path_targets = discovery.relabel.pod_logs.output
    }

    loki.source.file "pod_logs" {
      targets    = local.file_match.pod_logs.targets
      forward_to = [loki.write.platform.receiver]
    }

    // Tenant stamped here (overwritten at the hub edge for spokes). external_labels stamp e.g. cluster=<spoke>.
    loki.write "platform" {
      endpoint {
        url       = "${var.loki_push_url}"
        tenant_id = "${var.tenant_id}"
      }
      ${local.external_labels_block}
    }
  RIVER

  helm_values = {
    # Deterministic names; SA = <name>.
    fullnameOverride = var.helm_release_name

    crds = { create = false } # we deploy a plain log-collector DaemonSet; the chart CRDs (monitors) aren't used.

    # Drop the config-reloader sidecar: the River config is static (managed via Terragrunt/helm, which
    # rolls the DaemonSet on change). Removes a container + its CPU request so the pod fits packed nodes.
    configReloader = { enabled = false }

    serviceAccount = { create = true, name = local.sa_name }
    rbac           = { create = true } # ClusterRole: list/watch pods for discovery.kubernetes.

    controller = {
      type = "daemonset" # node-local file tailing (one Alloy per node).
    }

    alloy = {
      configMap       = { create = true, content = local.alloy_config }
      clustering      = { enabled = false }
      stabilityLevel  = "generally-available"
      enableReporting = false # no usage phone-home (cost/egress-conscious).

      mounts = {
        varlog = true # mount /var/log so loki.source.file can read /var/log/pods/*.
      }

      # discovery.kubernetes node-local filter reads this.
      extraEnv = [{
        name = "NODE_NAME"
        valueFrom = {
          fieldRef = { fieldPath = "spec.nodeName" }
        }
      }]

      # Minimal CPU request — a log collector idles low, and the cost-effective nodes run packed
      # (one sits ~98% CPU-requested). No CPU limit, so it can still burst. Memory limit only.
      resources = {
        requests = { cpu = "20m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Helm release — grafana/alloy (log-collector DaemonSet)
# ---------------------------------------------------------------------------

resource "helm_release" "alloy" {
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
