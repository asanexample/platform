# Learn: Cost & FinOps — Optimize: the cost levers (deep dive)

> Assumes the [Cost & FinOps orientation](orientation.md). That doc frames the whole loop —
> **Inform → Optimize → Operate** — and sketches the Optimize phase in a paragraph each. This deep dive
> teaches *one* phase, **Optimize**, properly: the four levers that actually reduce spend, how each is
> tuned *differently on the two clusters*, and the gotchas that bit us building them. If you only want the
> headline, the orientation has it; stay here to understand *why* the hub runs on-demand-only while preprod
> runs a spot node right now.

Optimize is the phase where seeing cost turns into *doing* something about it. Four levers are **built and
live**, and they split cleanly by *when* they act:

1. **Karpenter** — the biggest **continuous** lever (right-sizing + consolidation).
2. **Cluster parking** — the biggest **non-prod, scheduled** lever (lights-off overnight).
3. **The descheduler** — the **corrective** lever that makes the other two safe (re-seat the guests).
4. **`cost_profile` / `high_availability`** — the **build-time** lever that sizes the whole platform by one boolean.

Then one lever the platform deliberately *doesn't* pull — **Savings Plans** — because it fights lever 2.
We'll take them in that order.

---

## Lever 1 — Karpenter: the valet who re-parks the lot

The orientation's metaphor: Karpenter is *a valet who re-parks the whole lot continuously, picks the
right-sized space for each car, and closes empty aisles.* Here's the machinery under it.

**JIT provisioning — a NodePool is requirements, not a shape.** The old world (ADR-023) was
statically-sized [EKS managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html):
a fixed `desired` count of a fixed instance type, inert until a human edited it. [Karpenter](https://karpenter.sh/)
replaces that with a `NodePool` that expresses *requirements* — arch, capacity type, instance family, a
memory floor — and lets Karpenter pick the cheapest sufficient instance for the actual pending pods, in
seconds. The [NodePool template](https://github.com/asanexample/platform/blob/main/infra/modules/aws/karpenter/charts/nodepool/templates/nodepool.yaml)
is rendered by a small local Helm chart so the custom resources don't need the CRD present at plan time.

**Consolidation is the cost part.** Provisioning right-sized nodes saves money going *up*; the bigger
continuous win is coming *down*. The NodePool's `disruption` block carries two knobs —
`consolidationPolicy` and `consolidateAfter` — and *these two enums are the whole lever*, tuned oppositely
per cluster ([ADR-078](../../adrs/078-cluster-elasticity-karpenter.md) D4):

| | **platform (hub)** | **preprod** |
| --- | --- | --- |
| `capacity_types` | `["on-demand"]` | `["spot", "on-demand"]` |
| `consolidationPolicy` | `WhenEmpty` | `WhenEmptyOrUnderutilized` |
| `consolidateAfter` | `1m` | `1m` |

`WhenEmpty` (the hub) only reclaims a node once it is *fully empty* — it never disrupts a running pod. That
is deliberate: the hub carries the stateful singletons (Mimir, Loki, Tempo, Pyroscope, Keycloak, the CNPG
databases), and a valet who re-parks *occupied* cars would be moving a database mid-write. `WhenEmptyOrUnderutilized`
(preprod) is the aggressive version — it actively bin-packs workloads onto fewer nodes and reclaims the
underutilized ones. Preprod runs ephemeral tenant workloads that ArgoCD simply reschedules, so the churn is
free money.

**The spot correction — *not* "spot retired".** You will see the phrase "spot retired" (ADR-092's table
even uses it). Read it precisely: what ADR-078 D2 retired was the **static managed spot node *group*** — the
frozen ASG. **Spot as a capacity type is very much live.** Preprod's NodePool lists `spot`, and right now
it is running a spot node:

```text
# AWS_PROFILE=preprod kubectl --context preprod get nodeclaims
NAME                  TYPE        CAPACITY   ZONE         READY   AGE
default-…             m7g.large   spot       us-east-1c   True    101m
```

The hub, by contrast, is on-demand-only — again for stateful reliability, since a spot reclaim of a
database node is exactly the disruption `WhenEmpty` exists to avoid. So the two clusters demonstrate *both*
postures from one module: reliability-first on the hub, cost-first on preprod.

```text
# AWS_PROFILE=platform kubectl --context platform get nodeclaims
NAME                  TYPE         CAPACITY    ZONE         READY   AGE
default-…             r6g.medium   on-demand   us-east-1c   True    7h…
```

### Karpenter gotchas that teach

- **The 8 GiB node floor.** `min_instance_memory_mib = 6144` on *both* clusters excludes anything smaller
  than a `t4g.large`. Why: every node carries a fixed DaemonSet slab — Cilium, Beyla, Alloy, node-exporter,
  the OTel collector — that eats **~3.2 GiB** before a single workload pod lands. Let Karpenter pick a 4 GiB
  `t4g.medium` "to save money" and the kubelet exhausts memory and flaps `NotReady`. The cheap node is the
  expensive one. The floor is a `karpenter.k8s.aws/instance-memory Gt 6144` requirement in the NodePool.
- **The SCP exemption is mandatory, not optional.** Karpenter tags every instance it launches. The org SCPs
  `DenyTeamTagTampering` (on `ec2:CreateTags`) and `require-tagging` (on `ec2:RunInstances`) would `403`
  *every* launch — the controller silently provisions nothing — unless the anchored per-cluster
  `<cluster>-eks-karpenter-*` controller role (e.g. `platform-use1-eks-karpenter-*`, deliberately not a
  leading-wildcard `*-karpenter-*`) is in `exempt_roles`, alongside the Crossplane provisioners. Karpenter is a trusted platform provisioner
  that tags via the launch template, so it earns the exemption the same way they do.
- **The BYOCNI startup taint.** A fresh node is *not* `Ready` until Cilium is on it (the cluster is BYOCNI,
  ADR-009). If pods scheduled before the CNI, they'd land with no networking. The NodePool stamps a
  `node.cilium.io/agent-not-ready:NoSchedule` **startup taint**; Cilium removes it once its agent is up, and
  only then do application pods schedule (ADR-078 D5). Same Cilium-first constraint the old static groups
  had — just expressed in the NodePool instead of the managed-group bootstrap.

---

## Lever 2 — Cluster parking: lights off overnight

Karpenter shrinks the cluster to fit the load. **Parking** goes further on non-prod: `platctl down` scales
the managed node groups to `desiredSize=0` overnight, dropping *nearly all* compute cost. The orientation's
distinction is the one to hold: parking is *lights-off-overnight*, **not** *move-out-and-demolish*. The
control plane, every EBS/CNPG volume, and all cluster state are preserved; `up` brings it all back. A full
`platctl teardown` is the demolition — a different, destructive operation.

**The down/up ordering is the interesting part**, because a naive "scale the group to zero" would strand
Karpenter's own nodes. `platctl down` (per the `cluster-parking` skill) does it symmetrically:

- **down:** clear any `karpenter.sh/do-not-disrupt` holds → delete the **NodePool and EC2NodeClass together**
  (symmetric — see the gotcha) and poll until the NodeClaims are gone → scale the managed `system` group to
  `0`, draining while respecting PDBs → **force-terminate** any straggler still draining after ~2 min (a
  PDB-blocked lifecycle hook can't wedge a park) → stop the SSM bastion.
- **up:** wait for the cluster API *and* Tailscale to be back **before** re-applying the karpenter unit →
  recreate the NodePool + EC2NodeClass → run the recovery sweeps that restart workloads whose dependencies
  weren't ready at their startup.

### Parking gotchas that teach

- **After a park, `kubectl` is unreachable — and that's correct.** Scaling to zero also drops the in-cluster
  Tailscale subnet router that advertises the VPC CIDR, so the private EKS API (ADR-010) is no longer
  reachable and `kubectl` times out. This is *not* a failed park. **Verify a park via the AWS EKS API**
  (`aws eks describe-nodegroup … --query nodegroup.scalingConfig` → `desiredSize: 0`), never kubectl.
- **The down/up *asymmetry* trap.** `down` used to delete only the NodePool; on `up`, a leftover
  finalizer'd EC2NodeClass could lose a Terminating race and leave the NodePool present-but-not-ready with
  **zero workload capacity** (`karpenter logs: ignoring nodepool, not ready`). The fix was to delete *both*
  CRs symmetrically on down and assert *both* present on up — a reminder that lifecycle operations must be
  symmetric or they rot.
- **Unpark is a fresh admission of every pod.** Every workload re-schedules from cold, so `up` re-runs every
  admission webhook and re-derives every IAM/Pod-Identity binding — which *exposes latent bugs* that a
  long-running cluster was hiding (a startup-only DB client that connected before CoreDNS/ESO were ready is
  the classic victim). The operator lesson baked into the skill: **judge an unpark by pod *readiness*, not
  node state** — nodes `ACTIVE` says nothing about whether the pods on them came back healthy.

Parking is proven boringly repeatable — clean cycles logged across successive overnight runs — which is the
whole point: a cost lever you don't trust, you don't pull.

---

## Lever 3 — The descheduler: re-seat the guests

Here's the failure that makes the first two levers *dangerous* without the third. The kube-scheduler places
a pod onto a node **once** and never moves it. The platform's node set, though, is deliberately dynamic —
it parks, unparks, and consolidates. So consider a fleet of *single-replica* platform controllers
(argo-rollouts, external-dns, kube-state-metrics, the prometheus-agent operator). Each independently picks
"the emptiest node" at schedule time — which, right after an unpark, is the *same* first node up. They all
pile onto it. And `topologySpreadConstraints` (ADR-085) **do not help**: those spread the replicas *of one
workload*, not independent workloads, so a hundred one-replica Deployments still converge on one node.

The orientation's metaphor: the descheduler is *the restaurant host who re-seats guests so one table isn't
crammed while another sits empty.* The [module](https://github.com/asanexample/platform/blob/main/infra/modules/descheduler/main.tf)
runs the [kubernetes-sigs descheduler](https://github.com/kubernetes-sigs/descheduler) as a **CronJob**
(a periodic sweep, not a hot loop — the right shape for post-churn correction), running one strategy,
**`LowNodeUtilization`**: evict pods off nodes above the *overutilized* threshold so they reschedule onto
nodes below the *underutilized* threshold. Every eviction goes through the **`DefaultEvictor`** safety
envelope (ADR-093):

- **Respects PodDisruptionBudgets** — the ADR-085 workload PDBs and the CNPG database PDBs hold.
- **`nodeFit: true`** — a pod is evicted only if it could actually schedule elsewhere *right now*, so
  rebalancing never strands a pod `Pending` (the failure a naive `kubectl delete` hits).
- **`evictLocalStoragePods: false`** — never evict a pod with emptyDir/hostPath data.
- **Skips DaemonSets, static/mirror pods, and system-critical pods** (`evictSystemCriticalPods: false`) —
  Karpenter and CoreDNS stay put; relieving the hot node around them protects them indirectly.

**Per-cluster tuning**, because `LowNodeUtilization` only acts when *some* node qualifies as a destination
(below *all* underutilized thresholds):

| | **platform (hub)** | **preprod** |
| --- | --- | --- |
| schedule | `*/15 * * * *` | `*/10 * * * *` |
| underutilized | 40 % (module default) | **50 %** |
| overutilized | 70 % | 70 % |

Both are verifiably live (the CronJobs have been running for days):

```text
# platform            SCHEDULE       LAST SCHEDULE
kube-system  descheduler   */15 * * * *   11m
# preprod             SCHEDULE       LAST SCHEDULE
kube-system  descheduler   */10 * * * *   2m
```

Preprod's underutilized threshold is raised from the 40 % default to **50 %** for a precise reason — this is
the gotcha worth remembering.

### The 2026-07-02 meltdown — why 50 %, not 40 %

Post-unpark on preprod, one `t4g.large` absorbed **59 pods (~99 % CPU requests, 189 % memory-limits)** while
the other sat at **14 (~40 %)**. The overloaded node's kubelet degraded (`NodeStatusUnknown`), and every pod
on it crash-looped — **including Karpenter's own controller.** That's the deadlock: the component that would
add capacity was itself starved on the node it would have relieved. Capacity was never the problem — balanced
across the two nodes the workload fits at ~69 % each. It was *purely distribution*, and nothing corrected it.

Now the threshold arithmetic: the incident's cool node sat at **39 % CPU** — *one point under* the 40 %
default. Had the descheduler been running with the default, it would have judged that node "not
underutilized enough to be a destination" and done nothing. Raising preprod's underutilized threshold to
**50 %** gives the emptier of two small nodes reliable headroom to qualify as a rebalance target. The hub
keeps the calm 40 % default: it has more and bigger nodes, conservative `WhenEmpty` consolidation, and
stateful services where *fewer* evictions is better.

> **Where the host metaphor breaks:** a restaurant host re-seats a guest to a *known* empty table. The
> descheduler evicts and then trusts the *scheduler* to re-place the pod well — which is why `nodeFit`
> matters. Without it, the host would clear a crammed table and leave the guests standing in the doorway
> (`Pending`) because it never checked another table had room.

---

## Lever 4 — `cost_profile` / `high_availability`: the whole platform, sized by one boolean

The build-time lever. [`_base.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/_base.hcl)
defines `cost_profile` with two presets, `dev` and `prod`, each a bundle of toggles. Flip an environment to
`dev` and it fans out to a cheaper shape: `high_availability = false`, `single_az_nodes = true`, and the
durable LGTM+P stores **off** (`enable_mimir/loki/tempo/pyroscope = false` — Prometheus-only). Flip it to
`prod` and you get the full HA, multi-AZ, all-stores shape. The single derived boolean that does the most
downstream work is `high_availability`: it drives **replication factor 3 vs RF1**, Loki **SimpleScalable vs
SingleBinary**, and 2 vs 1 controller replicas (Karpenter reads it too). *The same platform, sized by one
boolean* — a per-knob override always wins over the preset, so an environment can opt into exactly one
prod-shaped piece.

**A correction while we're here — there is no S3 storage-class tiering.** It's tempting to assume the
observability buckets tier cold data to Glacier/IA as a cost lever. They don't. The lifecycle rules on the
Mimir/Loki/Tempo buckets are **version hygiene only**: `noncurrent_version_expiration` at 1 day plus
`abort_incomplete_multipart_upload` — they stop the *versioned* bucket growing unbounded, they do **not**
transition objects to a colder class. Retention of the actual telemetry is the **compactor's** job (it
deletes blocks past the retention window), not S3's. Don't teach S3 tiering as a cost lever here; it isn't one.

---

## The lever we deliberately don't pull — Savings Plans vs. parking

The biggest steady-state lever a *real* company has is a commitment purchase — **Savings Plans / RIs**,
a year of discounted compute. The platform **defers** it, for two independent reasons
([ADR-092](../../adrs/092-platform-finops-practice.md) D6): there's no spend budget to commit, and — the
teaching point — **it is in direct tension with lever 2.**

> **The gym-membership metaphor (orientation callback).** A Savings Plan is an annual gym membership: cheaper
> per visit *only if you actually go every day*. Parking the cluster is skipping the gym twelve hours a day.
> You don't buy an annual pass for a gym you lock overnight — committing to compute you then deliberately
> park means paying for it while it's turned off. **Where it breaks:** the two aren't wholly exclusive.
> There's a genuine **24/7 floor** — the always-on system pieces that *never* park (the control planes, the
> hub's stateful core). The resolution ADR-092 records: if ever budgeted, commit *only* to that un-parkable
> floor, never the elastic part that parks and consolidates away.

### Named-but-not-built (be honest)

All four levers above are built and running. For completeness, three Optimize items are *adopted in the
FinOps framework but not built*: AWS **Compute Optimizer** (#1055), **kube-green** for per-namespace
off-hours scaling (#1057), and **Cloud Custodian** the account-janitor (#1058) — plus **Savings Plans**,
documented-but-unbought (above). Crawl→Walk, honestly — see the
[Operate deep dive](deep-dive-operate-guardrails-and-the-practice.md) for the full tool verdicts.

---

## Gotchas that teach — the one-screen version

- **The cheap node is the expensive one.** A sub-8 GiB node can't hold the ~3.2 GiB DaemonSet slab and flaps
  `NotReady`. Hence `min_instance_memory_mib = 6144` on both clusters.
- **"Spot retired" is a half-truth.** The static spot *group* was retired; spot *capacity-type* is live —
  preprod runs a spot node now. The hub is on-demand-only on purpose (stateful reliability).
- **Consolidation policy is a reliability decision, not just a cost one.** `WhenEmpty` on the stateful hub
  *never* disrupts a running pod; `WhenEmptyOrUnderutilized` on preprod repacks aggressively. Same knob,
  opposite postures.
- **A parked cluster is unreachable by kubectl by design** — the Tailscale router is gone. Verify via the
  EKS API; judge an unpark by *pod readiness*, not node state. And `down`/`up` must be symmetric — the
  asymmetry that shipped once (NodePool deleted, EC2NodeClass not) left the cluster with zero capacity.
- **One percentage point matters.** Preprod's descheduler runs at 50 %, not the 40 % default, because the
  incident's cool node sat at 39 % — under a 40 % destination threshold it would never have rebalanced.
- **S3 lifecycle here is version hygiene, not tiering.** Retention is the compactor's job.

## Go deeper — source of truth

- **ADRs:** [ADR-078 Cluster Elasticity — Karpenter](../../adrs/078-cluster-elasticity-karpenter.md) ·
  [ADR-093 Descheduler for node rebalancing](../../adrs/093-descheduler-node-rebalancing.md) ·
  [ADR-092 Platform FinOps practice](../../adrs/092-platform-finops-practice.md) (D6 the SP/parking tension).
- **Module + unit code:**
  [`infra/modules/aws/karpenter`](https://github.com/asanexample/platform/blob/main/infra/modules/aws/karpenter/main.tf)
  (+ the [nodepool chart](https://github.com/asanexample/platform/blob/main/infra/modules/aws/karpenter/charts/nodepool/templates/nodepool.yaml)) ·
  [`infra/modules/descheduler`](https://github.com/asanexample/platform/blob/main/infra/modules/descheduler/main.tf) ·
  the per-cluster karpenter + descheduler
  [live units](https://github.com/asanexample/platform/blob/main/infra/live/aws/preprod/us-east-1/platform/karpenter/terragrunt.hcl) ·
  [`_base.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/_base.hcl) (the `cost_profile` presets).
- **House skills:** `cluster-parking` (the down/up ordering + the Learnings log), `platctl` (the orchestrator).
- **External (verified):**
  [Karpenter — Disruption](https://karpenter.sh/docs/concepts/disruption/) (consolidation policies; ~10 min) ·
  [Karpenter — NodePools](https://karpenter.sh/docs/concepts/nodepools/) (requirements vs shape; ~10 min) ·
  [kubernetes-sigs/descheduler](https://github.com/kubernetes-sigs/descheduler) (LowNodeUtilization + DefaultEvictor; ~15 min).
- Back to the [Cost & FinOps orientation](orientation.md), or across to the
  [Inform](deep-dive-inform-the-two-meters.md) and [Operate](deep-dive-operate-guardrails-and-the-practice.md) deep dives.
