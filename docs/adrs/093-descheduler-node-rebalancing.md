# ADR-093: Descheduler for node rebalancing

**Status:** Proposed

## Context

The Kubernetes scheduler places a pod onto a node once, at admission time, and never moves it. That is fine
for a static node set, but this platform's node set is deliberately dynamic:

- **Parking/unparking** (`platctl down`/`up`, cluster-parking skill) scales node groups to zero and back. On
  restore, nodes come up staggered, and every pod that schedules before the later nodes exist lands on the
  first node up.
- **Karpenter consolidation** (`WhenEmptyOrUnderutilized` on preprod) actively repacks workloads onto fewer
  nodes to save cost, and node replacement (drift, expiry, spot interruption) reshapes the set continually.

Nothing rebalances afterward. The single-replica platform controllers (argo-rollouts, external-dns, the
prometheus-agent operator, kube-state-metrics, …) each independently pick the emptiest node at schedule time —
which, right after unpark, is the *same* first node — and stay there. `topologySpreadConstraints` (ADR-085) do
not help: they spread the *replicas of one workload*, not independent workloads, so a fleet of one-replica
Deployments still converges on one node.

This bit us on 2026-07-02. Post-unpark, one preprod `t4g.large` absorbed **59 pods (~99% CPU requests, 189%
memory-limits)** while the other sat at **14 (~40%)**. The overloaded node's kubelet then degraded
(`NodeStatusUnknown`), and every pod on it crash-looped — **including Karpenter's own controller**, which
deadlocked autoscaling (the component that would add capacity was itself starved on the node it would have
relieved). Capacity was not the problem: balanced across the two nodes the workload fits at ~69% each. It was
purely a *distribution* problem, and there was no mechanism to correct it. Manual `kubectl delete` doesn't
reliably fix it either — the scheduler frequently re-places the pod on the same hot node.

## Decision

Deploy the [kubernetes-sigs descheduler](https://github.com/kubernetes-sigs/descheduler) on both clusters as a
periodic **CronJob** running the **`LowNodeUtilization`** strategy: evict pods from nodes above the
`overutilized` thresholds so they reschedule onto nodes below the `underutilized` thresholds.

- New shared module `infra/modules/descheduler` (Helm-based, house conventions), deployed per-cluster as a
  Terragrunt unit; chart version pinned in `_versions.hcl`.
- Default thresholds: underutilized `{cpu,memory,pods}=40%`, overutilized `=70%`, on a ~15-minute schedule.
  Both are per-cluster tunable.

Every eviction goes through the `DefaultEvictor` with conservative settings so rebalancing is safe:

- **Respects PodDisruptionBudgets** — the ADR-085 workload PDBs and the CNPG database PDBs are never violated.
- **`nodeFit: true`** — a pod is only evicted if it can be scheduled elsewhere *now*, so rebalancing never
  strands a pod `Pending`.
- **Skips** DaemonSet, static/mirror, and controller-less pods (chart defaults); **`evictLocalStoragePods:
  false`** (no data loss); **`evictSystemCriticalPods: false`** — Karpenter/CoreDNS stay put and are protected
  indirectly by relieving the hot node around them.

## Consequences

### Positive

- Post-unpark and post-consolidation imbalance self-corrects within a cron tick instead of persisting until a
  human notices — no more single-node meltdowns taking out Karpenter/observability.
- General benefit beyond parking: covers node replacement, spot churn, and consolidation repacking.
- Complements ADR-085 topology-spread (multi-replica spread) and Karpenter (adding/removing nodes) — this fills
  the "move existing pods between existing nodes" gap neither covers.

### Negative

- Introduces controlled pod churn: evicted pods restart, so single-replica services see brief blips. Bounded by
  the cron cadence and PDBs; acceptable for the platform controllers, and prod tenant workloads run ≥2 replicas
  (ADR-085 replica floor) so an eviction is zero-downtime.
- One more cluster add-on to keep version-aligned with the Kubernetes minor.

### Risks

- **Eviction churn / ping-pong** if the underutilized/overutilized band is too narrow — mitigated by the wide
  40/70 gap and `nodeFit`.
- **Chart/k8s version skew** — the descheduler tracks Kubernetes minors; the pin must be bumped with cluster
  upgrades (called out in `_versions.hcl` and the module README).

## Alternatives considered

- **A post-unpark rebalance step inside `platctl up`.** Narrower (fixes only the unpark path, not Karpenter
  consolidation or node replacement, which is what actually re-triggered the incident hours after unpark) and
  reinvents eviction safety the descheduler already has. Rejected as the primary fix; `platctl up` keeps its
  targeted recoveries (Karpenter readiness, Kyverno, DB-client ordering) for platctl-specific problems.
- **Pod anti-affinity / topology-spread on the platform controllers.** Doesn't help single-replica workloads
  (nothing to spread against) and hard anti-affinity risks unschedulability on a 2-node cluster.
- **Bigger / more preprod nodes.** Treats a distribution problem as a capacity problem — more cost for no
  rebalancing guarantee; the imbalance recurs on the next churn regardless of node size.
- **Do nothing / manual `kubectl delete`.** The recurring-toil status quo; unreliable (scheduler re-pins to the
  hot node) and leaves a window where a degraded node crash-loops critical controllers.

## Related

- ADR-085 (zero-downtime availability: PDBs, topology-spread, replica floor) — complementary; this fills the
  inter-node rebalancing gap.
- ADR-078 (Karpenter elasticity) — consolidation is one of the churn sources this corrects for.
- The cluster-parking skill's Learnings log (2026-07-02) — the incident that motivated this.
