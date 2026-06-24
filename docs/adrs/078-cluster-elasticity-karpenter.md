# ADR-078: Cluster Elasticity — Karpenter + Workload Autoscaling

**Status:** Accepted — Phase 1 (Karpenter) implemented + live on both clusters, 2026-06-23 (#643). Phase 2
(HPA/KEDA on the paved road) outstanding. Refines [ADR-023](023-managed-node-groups.md) (managed node groups
now bootstrap only the `system` floor; Karpenter owns workload capacity).

## Context

The platform has **no elasticity at any layer**. This is the single largest operational gap, and it
contradicts the platform's own positioning ("ship as fast as Vercel", "production-shaped").

- **Nodes don't scale.** There is no Karpenter and no Cluster Autoscaler; the EKS **managed node groups are
  statically sized** (`scaling_config` carries `min`/`desired`/`max`, but nothing *drives* `desired` — the
  bounds are inert). The platform cluster runs a small **system** group (on-demand `t4g.large`, 2 vCPU / 8 GiB)
  plus a fixed **spot workload** group. Pending pods do not summon new nodes; the cluster sits at whatever was
  applied.
- **Workloads don't scale.** No HPA, no KEDA, no VPA anywhere. A traffic spike adds no replicas.

The cost of this has been paid repeatedly during the observability build-out: a CPU-tight cluster
(~98 % CPU-requested), pods stuck `Pending`, and the manual remedy of hand-editing node-group sizes or running
`platctl` to scale. Every one of those was this gap. It is also the one axis where the reference platform is
*not* production-shaped: a cluster teams ship onto must absorb load.

The cluster is **BYOCNI** (Cilium installed before nodes are `Ready`, `bootstrap_self_managed_addons = false`,
ADR-009), **Graviton-first** (arm64, with a defined spot instance pool), and **cost-profile-driven** (`dev`
minimal / `prod` HA). Any elasticity solution must respect all three.

## Decision

Adopt a two-layer elasticity model:

1. **Node autoscaling → [Karpenter](https://karpenter.sh/)** (not Cluster Autoscaler). Karpenter owns
   **workload** capacity: it provisions right-sized nodes just-in-time for pending pods and **consolidates**
   them away when underused. A small fixed **system** node group remains (it's where Karpenter itself runs).
2. **Workload autoscaling → HPA (+ KEDA for event-driven)**, delivered **through the paved road** so teams get
   elasticity by construction rather than bolted on.

The two compose into the full loop: **HPA adds pods → Karpenter adds nodes → consolidation reclaims them when
load drops.**

## Design

### D1 — Karpenter over Cluster Autoscaler

Cluster Autoscaler is ASG-bound: it scales pre-defined node groups, needs a group per instance shape, reacts
slowly, and never bin-packs or consolidates. Karpenter is **instance-flexible** (a `NodePool` expresses
*requirements*, not a fixed shape), provisions in seconds, **bin-packs** pending pods onto the cheapest
sufficient node, and **consolidates** continuously. For a modern EKS platform — and especially a cost-tight,
park-when-idle one — consolidation is the decisive feature. Karpenter is the current EKS-native standard and
fits the platform's "latest, modern" ethos.

### D2 — A minimal system node group stays; Karpenter owns the rest

Karpenter cannot provision the node it runs on, so a small **managed system node group** remains for Karpenter,
CoreDNS, the Cilium operator, and other cluster-critical singletons (sized to the floor, on-demand for
stability). The existing **fixed spot workload group is retired** in favour of Karpenter `NodePool`s. This is
the standard split and keeps a stable base that doesn't disrupt itself.

### D3 — NodePools: Graviton-first, spot-allowed, instance-flexible, cost-profile-driven

`NodePool` requirements preserve and *improve* today's intent:

- **`kubernetes.io/arch: arm64`** (Graviton) as the default; the spot instance families (`t4g`/`m6g`/`m7g`,
  with x86 fallbacks) become Karpenter requirements rather than a frozen list — Karpenter picks the cheapest
  available shape per request.
- **`karpenter.sh/capacity-type: [spot, on-demand]`** — spot-preferred for workloads, on-demand fallback.
- **`cost_profile`-driven limits** (consistent with the existing toggle): `dev` gets tight CPU/memory caps and
  aggressive consolidation; `prod` gets higher ceilings, on-demand for critical pools, and disruption budgets.

### D4 — Consolidation is the cost lever

`disruption.consolidationPolicy: WhenEmptyOrUnderutilized` with a `consolidateAfter` to damp churn. On this
platform consolidation does double duty: it bin-packs under load **and** reclaims nodes when quiet — directly
attacking the ~98 %-requested / `Pending` pain and partially automating the manual park/unpark toil. Disruption
budgets cap how much can churn at once.

### D5 — BYOCNI / Cilium-first ordering on Karpenter nodes (the gotcha)

Because the cluster is BYOCNI, a fresh node is **not** `Ready` until Cilium is on it — and pods must not land
before then. Cilium runs as a DaemonSet, so it lands on Karpenter nodes automatically; the ordering is enforced
with a **startup taint** on the `NodePool` (e.g. a `node.cilium.io/agent-not-ready` taint that Cilium removes
once the agent is up), so application pods only schedule after the CNI is ready. This mirrors the Cilium-first
constraint the static node groups already satisfy (ADR-008/009) — it just has to be expressed in the
`NodePool`/`EC2NodeClass` instead of the managed-group bootstrap.

### D6 — Workload autoscaling is part of the paved road

Node autoscaling is half the loop; without pod autoscaling, replicas never grow and Karpenter has nothing to
provision *for*. So:

- **HPA** (CPU/memory, `autoscaling/v2`) is the default mechanism; **KEDA** is added for event-driven scaling
  (queue depth, etc.) when a product needs it.
- Crucially, the **golden-path skeleton / Crossplane Environment Composition emits a sane default HPA** so a
  new service is elastic by construction — the same "platform-injected, not app-wired" principle the
  instrumentation strategy uses (ADR-077). Teams opt *out*, not *in*.

### D7 — Spot interruption handling

Karpenter consumes the EC2 **interruption queue** (SQS) and gracefully drains a node ahead of a spot reclaim or
scheduled maintenance — strictly better than the current static spot group, which has no interruption handling
at all.

## Dependencies & sequencing

- **Phase 1 — Karpenter (nodes).** New `karpenter` module (Helm + the controller IAM via Pod Identity, the
  interruption SQS queue, `EC2NodeClass` + `NodePool`s). Keep the system node group; retire the spot workload
  group. Verify a burst of pending pods provisions a node and that idle nodes consolidate away.
- **Phase 2 — Workload autoscaling (paved road).** HPA defaults in the golden-path skeleton + the Environment
  Composition; KEDA module when first needed. Verify HPA → Karpenter → consolidation end to end with a load
  test (k6 is already in the stack).
- **Interactions:** must respect **BYOCNI/Cilium** (D5, ADR-008/009), the **Graviton/spot** intent, the
  **`cost_profile`** toggle, and **Pod Identity** for the controller (ADR-047). Karpenter consolidation
  reduces — but does not replace — `platctl` park/unpark (the system group still needs explicit scale-to-zero).

## Consequences

- **+** Real elasticity: the cluster absorbs load instead of going `Pending`, and shrinks when idle — closing
  the biggest "production-shaped" gap and a recurring operational tax.
- **+** Lower cost: consolidation + spot + Graviton bin-packing typically beats statically-sized groups,
  *especially* on a cost-tight reference cluster.
- **+** Paved-road consistent: services are elastic by construction (default HPA), no per-app plumbing.
- **+** Better spot posture: graceful interruption draining the static pool never had.
- **−** A new privileged cluster-critical controller to operate (Karpenter), plus the BYOCNI startup-taint
  subtlety (D5) — a real but well-trodden EKS pattern.
- **−** Consolidation causes deliberate pod churn; mitigated by `consolidateAfter`, disruption budgets, and
  PodDisruptionBudgets on critical workloads.
- **−** Capacity is no longer statically legible ("how many nodes do we have?" becomes "it depends on load") —
  the right trade, but it shifts the mental model and makes the observability cost dashboard more dynamic.

## Implementation notes (as-built, Phase 1)

Things the design didn't anticipate, learned applying it live (module `infra/modules/aws/karpenter`):

- **Org SCP exemption is mandatory.** The controller role must be in `exempt_roles`
  (`mgmt/global/organizations`, pattern `*-karpenter-*`) alongside the crossplane provisioners. Two SCPs block a
  non-exempt provisioner: `DenyTeamTagTampering` (the `Team` tag on `ec2:CreateTags`) and `require-tagging`
  (denies `ec2:RunInstances` when Environment/ManagedBy/Owner are absent from the *request* — Karpenter tags via
  the launch template, not RunInstances). This must be applied **before** Karpenter provisions, or every launch
  is a 403 — a real rebuild-ordering dependency.
- **EC2NodeClass `spec.tags`** must not carry `kubernetes.io/cluster/<name>` or `karpenter.*` keys (Karpenter
  manages them — they're rejected as invalid). The IAM policy needs **both** the CreateAction-scoped
  `AllowScopedResourceCreationTagging` *and* the standalone `AllowScopedResourceTagging` (the `nodeclaim.tagging`
  controller tags the instance after launch).
- **Minimum node size matters (D5 corollary).** The per-node DaemonSet slab (Cilium, Beyla, Alloy, node-exporter,
  otel) is ~3.2 GiB; a 4 GiB node exhausts memory and the kubelet flaps `NotReady`, churning. The NodePool sets a
  `karpenter.k8s.aws/instance-memory` floor (`min_instance_memory_mib = 6144` → 8 GiB+, matching the system group).
- **Park integration (subtler than it looks — verified live).** `platctl down` must, *before* scaling the
  managed groups to zero: (1) **clear `karpenter.sh/do-not-disrupt`** from the stateful pods — that annotation
  (steady-state protection against voluntary disruption) ALSO blocks Karpenter's termination drain, so the
  NodePool delete would otherwise hang on them; and (2) after deleting the NodePool, **poll until the NodeClaims
  are actually gone** — `kubectl delete nodepool` cascades to NodeClaim deletion in the *background* and returns
  early, so without the wait the controller (on the system group) is scaled to zero mid-termination and orphans
  the EC2 instances. The original "the NodePool finalizer blocks until drained" assumption was wrong on both
  counts. Then (3) the managed-group scale-to-zero itself drains each node via an EKS lifecycle hook that
  **respects PodDisruptionBudgets**, so the stateful pods that rescheduled onto the system nodes stall it in
  `Terminating:Wait` for the ~15 min hook timeout — `down` gives the graceful drain a short window then
  **force-terminates the stragglers** (a park is a full shutdown; EBS data persists). And on the way back, `up`
  must **wait for the cluster API** (restored nodes + Tailscale router) before applying the karpenter unit, else
  the apply fails and orphans its helm releases from TF state. `up` also re-applies the karpenter unit and the
  workloads' pod templates re-add the annotation.
- **System-node sizing is its own decision.** Node-pinned DaemonSet pods can't be served by Karpenter, so the
  fixed system group must itself be large enough to hold the DaemonSet slab + standing load — the platform system
  group went `t4g.large → t4g.xlarge`. Changing a managed group's `instance_types` is **ForceNew**
  (destroy-then-create; the module's `create_before_destroy` is only on the launch template + the group name is
  fixed) → a ~3-min hub blip, during which the in-cluster Tailscale subnet router is evicted so the private EKS
  API is briefly unreachable. Plan such changes as a deliberate, monitored step.
