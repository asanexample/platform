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

  # P13 per-team log isolation (#590): when enabled, derive the Loki tenant from each pod's Kyverno-injected
  # `team` label (present on env-namespace pods) and stamp it per stream; system pods with no team fall back to
  # the cluster tenant. This is the WRITE half — the loki-tenant-proxy enforces per-team reads. Off = unchanged
  # single-tenant behaviour. NB: for a spoke this requires the hub Loki ingest edge to PASS THROUGH the tenant
  # (not force-stamp) — a deferred write-integrity tradeoff hardened later by ingest mTLS (#590 Phase-4 D-2).
  # (heredocs kept out of the ternary — HCL rejects a heredoc directly in a `?:` true-branch.)
  retenant_rules_raw = <<-RULES

      // env-namespace pods carry `team` (Kyverno mutate) → per-team Loki tenant.
      rule {
        source_labels = ["__meta_kubernetes_pod_label_team"]
        target_label  = "tenant"
      }
      // system pods (no team label) → the cluster tenant.
      rule {
        source_labels = ["tenant"]
        regex         = "^$"
        target_label  = "tenant"
        replacement   = "${var.tenant_id}"
      }
  RULES

  retenant_process_raw = <<-PROC

    // Stamp X-Scope-OrgID from the per-stream `tenant` label, then drop it so it isn't indexed as a label.
    loki.process "retenant" {
      forward_to = [loki.write.platform.receiver]
      // Promote the app's OTel trace_id/span_id (in the JSON body) to Loki STRUCTURED METADATA (Loki 3.x) so the
      // log->trace jump is first-class instead of a query-time derived-field regex on the Grafana side. Extract
      // with a quote-free regex (the line is CRI-wrapped JSON; [^0-9a-f]+ spans the `":"` between key and value)
      // so no fragile escaping in this heredoc. Non-request logs simply don't match and carry no such metadata.
      // Additive + cheap: no line rewrite, and structured metadata (unlike index labels) doesn't add cardinality.
      stage.regex {
        expression = "trace_id[^0-9a-f]+(?P<trace_id>[0-9a-f]{32})"
      }
      stage.regex {
        expression = "span_id[^0-9a-f]+(?P<span_id>[0-9a-f]{16})"
      }
      stage.structured_metadata {
        values = {
          trace_id = "",
          span_id  = "",
        }
      }
      stage.tenant {
        label = "tenant"
      }
      stage.label_drop {
        values = ["tenant"]
      }
    }
  PROC

  retenant_rules   = var.per_team_tenant ? local.retenant_rules_raw : ""
  retenant_process = var.per_team_tenant ? local.retenant_process_raw : ""
  # loki.source.file forwards to the re-tenant processor when enabled, else straight to the writer.
  source_forward = var.per_team_tenant ? "loki.process.retenant.receiver" : "loki.write.platform.receiver"

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
      }${local.retenant_rules}
    }

    local.file_match "pod_logs" {
      path_targets = discovery.relabel.pod_logs.output
    }

    loki.source.file "pod_logs" {
      targets    = local.file_match.pod_logs.targets
      forward_to = [${local.source_forward}]
    }
    ${local.retenant_process}
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
