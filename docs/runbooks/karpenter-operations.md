# Runbook: Karpenter Operations

> **Purpose:** day-2 operations for Karpenter node autoscaling (ADR-078) — tuning the
> NodePool/EC2NodeClass, understanding consolidation/disruption, interruption handling, and
> debugging "pods stuck Pending, no nodes provisioned." Karpenter is live on **both**
> clusters. **Phase 2 (workload autoscaling) is now live too**: the paved road emits a default
> HPA and the full loop is proven — HPA scales pods → Karpenter provisions nodes → consolidation
> reclaims them on load drop (ADR-078 Phase 2, #1240). Only KEDA (event-driven) remains deferred.
>
> **Related ADR:** [078-cluster-elasticity-karpenter](../adrs/078-cluster-elasticity-karpenter.md),
> [085-workload-availability-graceful-disruption-defaults](../adrs/085-workload-availability-graceful-disruption-defaults.md)
> (the `terminationGracePeriod` drain backstop)
> **See also:** [cluster-scale-down-up.md](cluster-scale-down-up.md) (park/unpark — Karpenter drain ordering)
>
> **Last reviewed:** 2026-07-01

---

## What Karpenter manages

A single **NodePool** (`default`) + **EC2NodeClass** (`default`) per cluster
(`infra/modules/aws/karpenter`), owning **workload** capacity — a small fixed on-demand
**system** node group (managed node group, outside Karpenter) still covers system
DaemonSets/control-plane-adjacent pods (ADR-078 D2). Karpenter watches for unschedulable
pods, picks an instance type from its constraints, and provisions a `NodeClaim` → EC2
instance just-in-time; it also consolidates/reclaims nodes per its disruption policy.

## Live configuration (platform vs. preprod)

| Setting | Platform (hub) | Preprod |
|---|---|---|
| `capacity_types` | `["on-demand"]` — spot retired, stateful-safe | `["spot", "on-demand"]` — cost-optimized |
| `consolidation_policy` | `WhenEmpty` — never disrupts a running pod | `WhenEmptyOrUnderutilized` — bin-packs + reclaims |
| `consolidate_after` | `1m` | `1m` |
| `cpu_limit` / `memory_limit` | `32` vCPU / `128Gi` (conservative) | `48` vCPU / `192Gi` (aggressive) |
| `node_arch` | `arm64` (Graviton-first) | `arm64` |
| Instance families (arm64 default) | `t4g, m6g, m7g, c6g, r6g` | same |
| `min_instance_memory_mib` | `6144` (8 GiB+ floor) | `6144` |

Rationale for the platform/preprod split: the hub runs stateful workloads (Mimir/Loki/Tempo
ingesters, Keycloak, CNPG) paired with `karpenter.sh/do-not-disrupt` + PodDisruptionBudgets
— `WhenEmpty` guarantees Karpenter never evicts a running pod to consolidate. Preprod runs
ephemeral, ArgoCD-rescheduled tenant workloads, where aggressive bin-packing is a pure cost
win.

Live units: `infra/live/aws/platform/us-east-1/platform/karpenter/terragrunt.hcl` and the
preprod equivalent. Module: `infra/modules/aws/karpenter/` (chart templates under
`charts/nodepool/templates/{nodepool,ec2nodeclass}.yaml`).

## NodePool/EC2NodeClass tuning

- **Instance requirements** are hard constraints on the NodePool: `kubernetes.io/arch`,
  `kubernetes.io/os: linux`, `karpenter.sh/capacity-type`, `karpenter.k8s.aws/instance-family`
  (a list — Graviton families by default), and a **minimum instance memory floor**
  (`karpenter.k8s.aws/instance-memory >= 6144`). The floor exists because per-node
  DaemonSets (Cilium, Beyla, Alloy, node-exporter) consume **~3.2 GiB** baseline — a
  `t4g.medium` (4 GiB) exhausts kubelet memory and flaps `NotReady`. Don't lower this floor
  without accounting for the DaemonSet slab.
- **EC2NodeClass** resolves the AMI (`al2023@latest`, SSM-pinned per K8s version), reuses
  the **same node IAM role** as the managed system node group, sets `kubelet.maxPods: 110`
  (the Cilium overlay decouples pod count from ENI limits), and requires **IMDSv2** (hop
  limit 1).
- **`spec.tags` on the EC2NodeClass must NOT set `kubernetes.io/cluster/<name>` or any
  `karpenter.*` key** — Karpenter manages those itself and rejects a class that tries to
  override them.
- **The BYOCNI startup taint** (`node.cilium.io/agent-not-ready`, `NoSchedule`) is on every
  Karpenter-provisioned node by default — Cilium's DaemonSet removes it once the agent is
  ready on that node, so a workload pod can never schedule ahead of the CNI (ADR-078 D5).
  If a NodeClaim never leaves `NotReady`, check whether Cilium reconciled that node before
  assuming Karpenter is broken (see Debugging below).

## Consolidation & disruption

- **`consolidationPolicy`** — `WhenEmpty` only reclaims a fully-empty node (no eviction of
  running pods); `WhenEmptyOrUnderutilized` additionally bin-packs and evicts to consolidate
  underutilized nodes. `consolidateAfter: 1m` on both clusters is the grace period before a
  candidate node is acted on.
- **`terminationGracePeriod: 8h`** (ADR-085 backstop) bounds how long Karpenter will wait on
  a blocking PodDisruptionBudget or a `karpenter.sh/do-not-disrupt` annotation before it
  forcibly drains anyway. Without this, a single-replica workload with a tight PDB (or a
  stale `do-not-disrupt` annotation) can wedge consolidation, drift remediation, and AMI
  upgrades indefinitely.
- **`karpenter.sh/do-not-disrupt: "true"`** on a pod blocks Karpenter from evicting its node
  for consolidation/drift, subject to the 8h backstop above. On the platform cluster this
  should only be set on stateful pods that already carry a PDB (Mimir/Loki/Tempo ingesters,
  CNPG). List what's currently annotated:

  ```bash
  kubectl get pod -A -o jsonpath='{range .items[?(@.metadata.annotations.karpenter\.sh/do-not-disrupt=="true")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
  ```

- No `expireAfter` is configured on either cluster — nodes run indefinitely until
  consolidated or interrupted, not on a forced-age rotation.

## Interruption handling (spot, preprod only)

Both clusters provision an SQS interruption queue (`<cluster_name>-karpenter`, 300s message
retention) and four EventBridge rules feeding it: AWS Health events, EC2 Spot Interruption
Warning, EC2 Instance Rebalance Recommendation, and EC2 Instance State-change Notification.
The Karpenter controller (`settings.interruptionQueue`) drains a node gracefully ahead of an
actual spot reclaim. Since platform runs on-demand only, its queue/rules are wired but
effectively idle — **spot interruption only fires on preprod** today.

```bash
# Sanity-check the interruption queue is empty in steady state (preprod)
AWS_PROFILE=preprod aws sqs get-queue-attributes \
  --queue-url $(AWS_PROFILE=preprod aws sqs get-queue-url --queue-name preprod-use1-eks-karpenter --output text) \
  --attribute-names ApproximateNumberOfMessages --region us-east-1
```

## Debugging: pods stuck Pending, no nodes provisioned

Work through in order — `platctl validate` already runs the first check automatically
(`KarpenterReadyCheck`, added after a 2026-06-27 incident where a `NodeClassReady=False`
NodePool silently stranded every workload pod).

```bash
# 1. Is the NodePool actually Ready (not just present)?
kubectl get ec2nodeclass -o wide
kubectl get nodepool -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

# 2. Is the NodePool at its CPU/memory cap?
kubectl get nodepool default -o jsonpath='{.status.resources}'

# 3. Is the controller itself healthy?
kubectl get pod -n karpenter -l app.kubernetes.io/name=karpenter -o wide
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -iE "error|warn" | tail -20

# 4. Any NodeClaims stuck mid-provision?
kubectl get nodeclaims -o wide
kubectl describe nodeclaim <name> | grep -A10 "Status\|Conditions"

# 5. Why is the specific pod Pending?
kubectl describe pod -n <ns> <name> | grep -A5 "Events:"
# "no matching nodes"       → NodePool requirements (arch/capacity-type/family) don't fit the pod
# "insufficient <resource>" → NodePool hit its cpu_limit/memory_limit
# no NodeClaim appears at all → Karpenter itself isn't scheduling (check controller logs, step 3)

# 6. Node exists but pod still won't land — check the BYOCNI startup taint
kubectl get node <name> -o jsonpath='{.spec.taints}' | grep cilium
kubectl logs -n cilium -l k8s-app=cilium --tail=50 | grep -i "agent ready"
```

`NodeClassReady=False` most often means the EC2NodeClass a NodePool references doesn't
exist or has a stuck finalizer — see the park/unpark note below for how that can happen.

## Park/unpark interaction

Karpenter must be drained **before** the system node group scales to zero, not the other
way around — scaling the system group mid-drain kills the controller pod and orphans the
EC2 instances it was tearing down. `platctl down`/`up` (or the `cluster-parking` skill)
handle the exact ordering; the two traps worth knowing about here:

- **`kubectl delete nodepool` does not block** — it cascades to NodeClaim deletion in the
  background and returns immediately. The park sequence must **poll `kubectl get
  nodeclaims` until empty** (up to ~6 min) before proceeding, not just fire-and-forget the
  delete.
- **The EC2NodeClass must be deleted symmetrically with the NodePool on park.** An earlier
  version of the park logic deleted only the NodePool, leaving the EC2NodeClass behind;
  on the next `up`, the force-replaced NodePool referenced a class with a stuck finalizer,
  leaving `NodeClassReady=False` and every workload `Pending` (the 2026-06-27 incident that
  motivated `KarpenterReadyCheck`). Fixed in `platctl down`/`up` — don't hand-roll a partial
  delete during a manual park.
- Also clear any `karpenter.sh/do-not-disrupt` annotations before park — they block the
  drain the same way they block ordinary consolidation.

## Known gotchas

- **Org SCP exemption is a hard prerequisite.** The Karpenter controller role must match
  the exempted-role pattern before it can provision *anything* — two org SCPs
  (`DenyTeamTagTampering`, a tagging-enforcement policy) otherwise block it. This is a
  rebuild-ordering dependency, not a runtime toggle — see
  [modify-scps.md](modify-scps.md)/[incident-scp-blocking.md](incident-scp-blocking.md) if a
  from-scratch bootstrap or SCP change breaks Karpenter provisioning.
- **IAM policy duality:** the controller role needs *both* `AllowScopedResourceCreationTagging`
  (tags applied at launch) and `AllowScopedResourceTagging` (post-launch tagging by
  Karpenter's own `nodeclaim.tagging` controller) — missing either one silently breaks
  tag-based cost allocation or SCP compliance without blocking provisioning itself.

## References

- [ADR-078](../adrs/078-cluster-elasticity-karpenter.md) — the decision, Phase 1/2 split, D1–D7
- [ADR-085](../adrs/085-workload-availability-graceful-disruption-defaults.md) — the `terminationGracePeriod` drain backstop
- [cluster-scale-down-up.md](cluster-scale-down-up.md) — park/unpark, the full drain-ordering runbook
- `infra/modules/aws/karpenter/` — module + NodePool/EC2NodeClass chart templates
- `cmd/platctl/internal/validate/checks.go` — `KarpenterReadyCheck`
