locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  descheduler_values = {
    # Run as a CronJob (the chart default): a periodic sweep is the right shape for rebalancing after node churn
    # (unpark, Karpenter consolidation, node replacement) rather than a hot loop.
    kind     = "CronJob"
    schedule = var.schedule

    podLabels = local.k8s_labels
    resources = var.resources

    deschedulerPolicyAPIVersion = "descheduler/v1alpha2"
    deschedulerPolicy = {
      profiles = [
        {
          name = "rebalance"
          pluginConfig = [
            {
              # The DefaultEvictor is the safety envelope every strategy evicts through. Defaults already
              # protect the things we must never move: it respects PodDisruptionBudgets (so the ADR-085 PDBs
              # and the CNPG database PDBs hold), and it skips DaemonSet pods, static/mirror pods, and pods
              # with no controller owner. We tighten it further below.
              name = "DefaultEvictor"
              args = {
                # nodeFit: only evict a pod if it could actually be scheduled onto another node right now —
                # so rebalancing never strands a pod Pending (the failure mode a naive `kubectl delete` hits).
                nodeFit = true
                # Never evict pods with local storage (emptyDir/hostPath) — eviction would drop their data.
                evictLocalStoragePods = false
                # Leave system-critical pods (priorityClass >= system-cluster-critical, e.g. Karpenter, CoreDNS)
                # in place; rebalancing the ordinary workloads off a hot node protects them indirectly.
                evictSystemCriticalPods = false
              }
            },
            {
              # LowNodeUtilization moves pods off OVER-utilized nodes onto UNDER-utilized ones — the exact
              # post-unpark disease: the first node up absorbs everything (~99% CPU) while later nodes sit idle
              # (~40%), and nothing rebalances (ADR-093). thresholds = "underutilized" destinations;
              # targetThresholds = "overutilized" sources.
              name = "LowNodeUtilization"
              args = {
                thresholds       = var.underutilized_thresholds
                targetThresholds = var.overutilized_thresholds
              }
            },
          ]
          plugins = {
            balance = {
              enabled = ["LowNodeUtilization"]
            }
          }
        },
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Descheduler (kubernetes-sigs) — rebalances pods off over-utilized nodes (ADR-093). Post-unpark and after
# Karpenter consolidation, pods pile onto whichever node comes up first and never rebalance; a node pinned at
# ~99% CPU degrades its own kubelet and crash-loops everything on it (Karpenter included). This is the
# cluster-native rebalancer that prevents that, evicting only through PDB-respecting, node-fitting safety rules.
# ---------------------------------------------------------------------------

resource "helm_release" "descheduler" {
  count = local.create ? 1 : 0

  name       = "descheduler"
  repository = "https://kubernetes-sigs.github.io/descheduler/"
  chart      = "descheduler"
  version    = var.helm_chart_version
  namespace  = var.namespace

  wait    = var.helm_wait
  timeout = 600

  values = [yamlencode(local.descheduler_values)]
}
