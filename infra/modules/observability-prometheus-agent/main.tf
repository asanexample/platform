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
  _rw_cluster = var.remote_write_url != "" ? [{
    url = var.remote_write_url
    # Snappy-compressed by default; modest queue so a hub outage buffers in the WAL rather than dropping.
    queueConfig = { capacity = 10000, maxSamplesPerSend = 2000, maxShards = 10 }
    # Uniform object shape (Terraform ?: rule): the per-team entry below carries writeRelabelConfigs, so this
    # one carries an empty (no-op) list.
    writeRelabelConfigs = []
  }] : []

  # P13 per-team DUAL-WRITE (#590): a SECOND remote_write to cortex-tenant (via its own edge hostname), with a
  # forced 2-step relabel that derives `route_tenant` from the namespace (unconditional `platform`, so a pod
  # can't spoof it, then override to the team for env namespaces). cortex-tenant splits by route_tenant into
  # per-team tenants. Additive: the cluster write above (the `preprod` tenant + all its consumers) is untouched.
  _rw_per_team = var.per_team_write_url != "" ? [{
    url         = var.per_team_write_url
    queueConfig = { capacity = 10000, maxSamplesPerSend = 2000, maxShards = 10 }
    writeRelabelConfigs = [
      { sourceLabels = ["namespace"], regex = ".*", targetLabel = "route_tenant", replacement = "platform" },
      { sourceLabels = ["namespace"], regex = "([a-z0-9]+)-[a-z0-9-]+-(dev|test|uat|staging|prod)", targetLabel = "route_tenant", replacement = "$1" },
    ]
  }] : []

  remote_write = concat(local._rw_cluster, local._rw_per_team)

  # kube-state-metrics CustomResourceState (ADR-091): emit team_budget_monthly_usd{team} from the Team CR's
  # spec.envelope.budget.monthlyUSD — the single source — so the cost dashboard/alerts compare spend vs budget.
  # Always rendered (avoids a conditional-type clash); only `enabled` toggles it, gated to the spoke that runs
  # the env-API Team CRD (the RBAC to read Team CRs is harmless when off).
  ksm_values = {
    rbac = {
      extraRules = [{
        apiGroups = ["platform.refplat.org"]
        resources = ["teams"]
        verbs     = ["list", "watch"]
      }]
    }
    customResourceState = {
      enabled = var.enable_team_budget_metric
      config = {
        spec = {
          resources = [{
            groupVersionKind = { group = "platform.refplat.org", version = "v1beta1", kind = "Team" }
            metricNamePrefix = "team"
            metrics = [{
              name = "budget_monthly_usd"
              help = "Team monthly cost budget in USD (ADR-091 cost guardrails)"
              each = {
                type  = "Gauge"
                gauge = { path = ["spec", "envelope", "budget", "monthlyUSD"] }
              }
              labelsFromPath = { team = ["metadata", "name"] }
            }]
          }]
        }
      }
    }
  }

  # ---- kube-prometheus-stack in AGENT mode: scrape-and-ship only, no UI / no alerting / no local query. ----
  helm_values = {
    # CRDs (ServiceMonitor, ...) are owned by the dedicated prometheus-operator-crds unit, installed early
    # to break the from-scratch bootstrap deadlock (a ServiceMonitor-shipping chart otherwise runs before the
    # stack that provides the CRD). Defer to it here so there is a single CRD owner (no Helm ownership clash).
    crds = { enabled = false }

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
          requests = { cpu = "100m", memory = var.memory_request }
          limits   = { memory = var.memory_limit }
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
    "kube-state-metrics" = local.ksm_values
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

# OTLP ingress to the OTel collector for TENANT apps that emit telemetry (P14 log→trace / ADR-077 Layer 1).
# default-deny-ingress otherwise drops cross-namespace OTLP, so an SDK-instrumented environment's export times
# out. Scoped like the hub's `allow-otlp-from-platform-telemetry`: only the collector pod, only the OTLP ports
# (4317 gRPC / 4318 HTTP), only from namespaces labeled `platform.refplat.org/otel-export = "true"` (the
# Crossplane Environment Composition stamps that label on environment namespaces). Opt-in per spoke.
resource "kubernetes_network_policy_v1" "allow_otlp_from_environments" {
  count = local.create && var.enable_otlp_ingress ? 1 : 0

  metadata {
    name      = "allow-otlp-from-environments"
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "opentelemetry-collector"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "platform.refplat.org/otel-export" = "true"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "4317"
      }
      ports {
        protocol = "TCP"
        port     = "4318"
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
