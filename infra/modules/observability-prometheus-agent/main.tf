locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC-1123), matching the other observability modules.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  cluster_label = var.cluster_label != "" ? var.cluster_label : var.cluster_name

  # Remote-write to the hub Mimir spoke-ingest edge. The hub Gateway force-sets X-Scope-OrgID per-hostname,
  # so we send NO tenant header here (any value would be overwritten at the edge). Empty url = off.
  remote_write = var.remote_write_url != "" ? [{
    url = var.remote_write_url
    # Snappy-compressed by default; modest queue so a hub outage buffers in the WAL rather than dropping.
    queueConfig = { capacity = 10000, maxSamplesPerSend = 2000, maxShards = 10 }
  }] : []

  # ---- kube-prometheus-stack in AGENT mode: scrape-and-ship only, no UI / no alerting / no local query. ----
  helm_values = {
    fullnameOverride = var.helm_release_name

    # A spoke ships to the hub; it has no Grafana, no Alertmanager, and evaluates no rules (the hub owns
    # alerting + dashboards). This is what makes it "lightweight" despite reusing the full chart.
    grafana      = { enabled = false }
    alertmanager = { enabled = false }
    defaultRules = { create = false }

    # --- EKS accuracy: managed control plane is unscrapeable; Cilium replaces kube-proxy. ---
    kubeScheduler         = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    # --- Prometheus in agent mode (WAL + remote_write; no TSDB query path). ---
    prometheus = {
      agentMode = true
      prometheusSpec = {
        replicas = var.high_availability ? 2 : 1
        # Tag every series with the source cluster so the hub isolates this spoke under its tenant.
        externalLabels = { cluster = local.cluster_label }
        remoteWrite    = local.remote_write
        # Discover ServiceMonitors / PodMonitors cluster-wide (KSM, node-exporter, kubelet), not just
        # chart-labelled ones. Rules are irrelevant in agent mode (no evaluation).
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        probeSelectorNilUsesHelmValues          = false
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { memory = "1Gi" }
        }
        # WAL storage: a PVC (durable across pod restarts during a hub outage) when storage_class names a
        # class that exists on the spoke cluster, else an ephemeral emptyDir (operator default when
        # storageSpec is null) — portable to any cluster. The remote_write queue still buffers either way.
        storageSpec = var.storage_class != "" ? {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = var.wal_size } }
            }
          }
        } : null
        podAntiAffinity = var.high_availability ? "hard" : "soft"
      }
    }

    # node-exporter needs host access — the ns is created (below) with PSA `privileged` for it.
    "kube-state-metrics" = {}
    nodeExporter         = { enabled = true }
  }
}

# ---------------------------------------------------------------------------
# Namespace (PSA `privileged` for node-exporter; created here, NOT by the chart, so the label is set —
# and intentionally NO tenant label, so Kyverno tenant policies don't apply; `observability` is also in
# the policy exclude_namespaces). Mirrors the hub observability module.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "this" {
  count = local.create ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(local.k8s_labels, {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "app.kubernetes.io/managed-by"       = "terraform"
    })
  }
}

# ---------------------------------------------------------------------------
# Network policies — default-deny ingress + allow intra-namespace (so the agent scrapes KSM/node-exporter
# in-namespace). Egress is left open: the agent scrapes cluster-wide and remote_writes to the hub edge.
# ---------------------------------------------------------------------------

resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  count = local.create ? 1 : 0

  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_intra_namespace" {
  count = local.create ? 1 : 0

  metadata {
    name      = "allow-intra-namespace"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Helm release — kube-prometheus-stack (agent mode)
# ---------------------------------------------------------------------------

resource "helm_release" "agent" {
  count = local.create ? 1 : 0

  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = kubernetes_namespace_v1.this[0].metadata[0].name
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [yamlencode(local.helm_values)]

  depends_on = [
    kubernetes_network_policy_v1.default_deny_ingress,
    kubernetes_network_policy_v1.allow_intra_namespace,
  ]
}
