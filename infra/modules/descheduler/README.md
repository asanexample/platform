# descheduler

Deploys the [kubernetes-sigs descheduler](https://github.com/kubernetes-sigs/descheduler) as a periodic
CronJob that **rebalances pods off over-utilized nodes** onto under-utilized ones (ADR-093).

## Why

The Kubernetes scheduler places a pod once and never moves it. After events that reshape the node set —
**parking/unparking** (`platctl down`/`up`), **Karpenter consolidation**, or a node replacement — pods pile onto
whichever node comes up first and stay there. Observed on 2026-07-02: post-unpark, one preprod node absorbed
59 pods (~99% CPU / 189% memory-limits) while another sat at 14 pods (~40%); the overloaded node's kubelet then
degraded (`NodeStatusUnknown`) and crash-looped everything on it — including Karpenter's own controller, which
deadlocked autoscaling. `topologySpreadConstraints` (ADR-085) don't help here: they only spread *multiple
replicas* of one workload, not the independent single-replica controllers that each greedily pick the emptiest
node at schedule time.

The descheduler is the cluster-native fix: it periodically evicts pods from nodes over the `overutilized`
thresholds so they reschedule onto the emptier ones.

## Safety

Every eviction goes through the `DefaultEvictor`, configured conservatively:

- **Respects PodDisruptionBudgets** — the ADR-085 workload PDBs and the CNPG database PDBs are never violated.
- **`nodeFit: true`** — a pod is only evicted if it can actually be scheduled elsewhere right now, so
  rebalancing never strands a pod `Pending`.
- **Skips** DaemonSet pods, static/mirror pods, and pods with no controller owner (chart defaults).
- **`evictLocalStoragePods: false`** — pods with `emptyDir`/`hostPath` are left alone (no data loss).
- **`evictSystemCriticalPods: false`** — `system-cluster-critical` pods (Karpenter, CoreDNS) stay put;
  rebalancing the ordinary workloads off a hot node protects them indirectly.

## Usage

Deployed per-cluster as a Terragrunt unit (`infra/live/aws/<env>/.../descheduler`). The chart version is pinned
in `infra/live/aws/_versions.hcl` (`helm_versions.descheduler`); keep it aligned with the cluster's Kubernetes
minor. Tune `schedule` and the `underutilized_thresholds` / `overutilized_thresholds` per cluster if needed.
