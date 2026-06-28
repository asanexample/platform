# ADR-085: Workload Availability — Graceful Draining & Disruption-Tolerance Defaults

**Date:** 2026-06-26

**Status:** Accepted — built + live on both clusters (2026-06-26); replica-floor flipped Audit → Enforce 2026-06-27 (#934). Graceful-drain/PDB/topology-spread defaults and the prod replica-floor are admission-enforced by the `policy` module.

## Context

The platform offers no **zero-downtime deployment** capability today. The substrate is good — Kyverno enforces
`readiness`/`liveness` probes and resource requests/limits ([ADR-014](014-kyverno-as-policy-engine.md)), the scaffolder
ships `replicas: 2`, traffic flows through the Cilium Gateway API ([ADR-017](017-gateway-api-over-ingress.md)) — but the
primitives that make a rollout (and an involuntary or platform-induced disruption) actually non-dropping are **entirely
absent**. A repo-wide search finds **no** `preStop` hooks, no `terminationGracePeriodSeconds`, no
`topologySpreadConstraints`, and **no `PodDisruptionBudget`** anywhere in tenant manifests, the `policy` module, or the
scaffolder.

"Zero-downtime deployment" actually bundles **two separable problem domains**, and conflating them is the usual mistake:

1. **Traffic correctness during the pod lifecycle** — not dropping in-flight or new connections when a pod goes away.
   This fires on *every* rolling update **and** every disruption (node consolidation, EKS upgrade, `platctl` park). It is
   app-agnostic and cheap to pave.
2. **Release safety** — catching a *bad version* before it takes prod down: canary, metric-gated promotion, automatic
   rollback. This is [ADR-056](056-progressive-delivery-and-safe-rollback.md).

Most platforms over-index on (2) — the visible canary dashboards — while still silently resetting connections on every
deploy because they never fixed (1). **This ADR owns domain (1): the foundational availability tier.** It is independent
of, and a prerequisite for, ADR-056 — progressive delivery is only meaningful on top of a foundation that doesn't drop
traffic in the first place.

Two facts make this acute and tractable:

- **Karpenter consolidation is live** ([ADR-078](078-cluster-elasticity-karpenter.md)). Voluntary node disruption now
  happens continuously, and with no `PodDisruptionBudget` and no topology spread, a single consolidation, upgrade, or
  park can evict every replica of a service at once. (Note: ADR-078's "disruption budgets" are *NodePool* budgets that cap
  *node* churn rate — they are **not** Pod PDBs and do nothing to protect a workload's replica floor.)
- **EKS runs Kubernetes 1.35.** The native pod `lifecycle.preStop.sleep.seconds` (`SleepAction`, KEP-3960) is **GA** as of
  1.34, so graceful-drain defaults can be injected without shipping a shell — which matters because the platform's images
  are distroless ECR builds where an `exec: ["sleep", …]` hook would fail.

## Decision

Pave the foundational availability tier as **defaults injected through machinery the platform already runs**, keyed by
tier/stage rather than left to per-app guesswork. Five design points.

### D1 — Scope: traffic correctness + disruption tolerance, not release safety

This tier makes every deploy and every voluntary/involuntary disruption **non-dropping**, regardless of whether canary is
ever built. [ADR-056](056-progressive-delivery-and-safe-rollback.md) (version safety) layers on top of it later. The two
are decoupled on purpose.

### D2 — Graceful draining defaults via the existing `mutate-pod-defaults` patch

Extend the existing `add-pod-defaults` Kyverno mutate rule (`policy` module) — the same add-if-absent strategic-merge
patch that already injects the hardened `securityContext` — to also inject, **when absent**:

- **`lifecycle.preStop.sleep.seconds: 10`** on each container, using the **native `SleepAction`** (GA on 1.35; no shell,
  so it is safe on distroless images). This delays SIGTERM so endpoint-deprogramming wins the termination race.
- **`terminationGracePeriodSeconds: 30`** at pod level (must exceed the preStop sleep plus the app's drain budget).

Both stay in the **single** `add-pod-defaults` patch. This is deliberate: keeping one strategic-merge block preserves the
property that Kyverno **autogen** can relocate the patch cleanly under `spec.template.spec` for every controller kind
(Deployment/StatefulSet/…). `preStop` sits at the same per-container depth as the existing `securityContext` injection;
`terminationGracePeriodSeconds` sits at the same pod-spec depth as the existing `automountServiceAccountToken` default.

**`topologySpreadConstraints` is handled separately, not in this `add-pod-defaults` patch.** A spread constraint's
`labelSelector` must match the *workload's own* pods, and a static strategic-merge patch on the pod spec has no per-workload
label data (an empty selector silently spreads nothing). The fix (built, #846) is the same **derive-from-trigger** technique
D3 uses for the PDB: a separate mutate (`mutate-topology-spread`) that **matches the controller directly** (Deployment/
StatefulSet, not the Pod via autogen) so it can read `request.object.spec.selector.matchLabels` and inject it as the spread
`labelSelector` (`maxSkew: 1` across `kubernetes.io/hostname` and `topology.kubernetes.io/zone`, `whenUnsatisfiable:
ScheduleAnyway` so a small/scaling-from-zero cluster doesn't strand pods `Pending`, with `matchLabelKeys: [pod-template-hash]`
so skew is computed per-revision). add-if-absent, so the scaffolder skeleton's explicit static spread is never overridden;
applies on admission, so existing workloads pick it up on their next deploy.

**Honest scope of D2.** Cilium's `enable-k8s-terminating-endpoint` (terminating-but-serving) is on by default, so it
already protects *established* connections and the *last-replica* new-connection case. The preStop sleep closes the
*residual new-connection race* during a normal rolling update — it **reduces, not removes**, reliance on the CNI default,
and the two are used together. What the platform **cannot** inject is the app's own SIGTERM handling (stop accepting,
drain in-flight, close listeners): the preStop sleep buys the *propagation* window, but only the app drains *in-flight*
work. That is a documented app contract (D6), not an enforced default.

### D3 — Disruption tolerance: PDBs via Kyverno `generate` (not the Composition)

Protect workloads from voluntary disruption with a `PodDisruptionBudget` of **`maxUnavailable: 1`**, created by a Kyverno
**`generate`** rule triggered on `Deployment`/`StatefulSet` in environment namespaces. The generated PDB's
`.spec.selector` is **copied from the trigger workload's own `spec.selector.matchLabels`**.

This deliberately rejects the first instinct — generating the PDB in the Crossplane `XEnvironment` Composition. The
Composition iterates **per service** (`$svc`), but the workload's pods carry **no service-distinguishing label** (they are
labeled `app: app-<team>-<product>`, product-level). The Composition knows `$svc`; the pods don't — so a
Composition-generated PDB cannot build a selector that matches. Deriving the selector from the trigger workload instead is
**label-convention-agnostic** (it matches whatever the workload actually uses), **retroactive** (covers existing and
hand-written workloads, not only scaffolded ones), **undeletable** (`synchronize: true` reconciles it back), and
**multi-service-safe by construction** (one PDB per Deployment). It also keeps PDBs in the `policy` module alongside the
rest of the admission guardrails.

**`maxUnavailable` is mandatory, not stylistic.** A `minAvailable`-based PDB on a single-replica workload (or a percentage
that rounds to "allow zero") permits **zero** voluntary evictions — `kubectl drain`, EKS upgrades, and **Karpenter
consolidation all hang forever**. `maxUnavailable: 1` always permits at least one eviction, so a drain completes
regardless of replica count, and it provides real protection once replicas ≥ 2 (D4).

### D4 — Replica floor: validate `≥ 2`, prod-stage only, never mutate

A `maxUnavailable: 1` PDB and a topology spread are meaningless on a single replica. Enforce **`replicas ≥ 2`** with a
Kyverno **validate** rule, scoped to **prod-stage** namespaces (matched by the `*-prod` namespace-name glob — the existing
`namespace-governance` pattern, since there is no per-stage chart value). Dev/test/uat stay at 1 replica for cost.

This is the **one** place hard enforcement (reject) is warranted; everything else in this ADR is a silent, overridable
default. Replicas are **validated, never mutated** — mutating `replicas` would fight the HPA ([ADR-078](078-cluster-elasticity-karpenter.md))
and the prod Kustomize overlay.

### D5 — Karpenter backstop: bound how long a stuck PDB can block disruption

Set **`spec.template.spec.terminationGracePeriod`** on the Karpenter `NodePool`(s). This bounds how long *any* blocking
PDB (or `karpenter.sh/do-not-disrupt` pod) can stall voluntary disruption before Karpenter forcibly drains — the safety
valve that makes a permissive, self-service PDB default safe even against a badly hand-written PDB, so a single workload
can never wedge node lifecycle or an EKS upgrade indefinitely.

### D6 — Paved-by-default, visible in the scaffolder, documented where it can't be enforced

The mutate/generate/validate machinery makes the defaults apply to **all** environment workloads, invisibly and
overridably — exactly like the existing `securityContext` injection. The scaffolder skeleton additionally carries
**visible** copies (preStop/grace in the base, the replica floor already in the prod overlay) so the zero-downtime shape
is teachable, not magic. The app-side SIGTERM contract and the long-lived-connection caveat (below) are documented in the
`authoring-k8s-workloads` skill; they are app responsibilities the platform surfaces but cannot inject.

## Verification

The only honest acceptance test for "zero downtime" is **observed**: a **k6** load test (already in the LGTM+P stack)
driving steady traffic through the Gateway while, in turn, we trigger (a) a `kubectl rollout restart`, (b) a Karpenter
consolidation (cordon + drain a node), and (c) a `platctl` park/unpark — asserting **zero non-2xx and zero connection
resets** across all three. Without this, "zero downtime" is a claim, not a fact. The obs stack makes it measurable.

## Consequences

### Positive

- **Every deploy and every disruption stops dropping traffic** — the silent every-rollout gap and the live Karpenter /
  upgrade / park risk are both closed by defaults, with no per-app work.
- **Reuses existing machinery** — extends one mutate patch, adds one generate rule and one validate rule; no new
  infrastructure, no new module.
- **Foundation for [ADR-056](056-progressive-delivery-and-safe-rollback.md)** — progressive delivery becomes meaningful on
  a base that already drains gracefully.
- **PDB selector derived from the workload** is correct for multi-service products before the multi-service label
  convention even exists.

### Negative

- **Defaults are invisible** (like the existing securityContext mutate) — a dev reading their manifest won't see the
  injected preStop/spread. Mitigated by the visible scaffolder copies (D6).
- **`replicas ≥ 2` on prod is a new rejection** — a real (if small) friction, and a cost floor for prod environments.

### Risks

- **Kyverno `generate` selector + autogen (implementation risk).** Copying `request.object.spec.selector.matchLabels` into
  a generated PDB is a standard pattern but must be proven in the offline `.kyverno-tests` harness — including the
  generate-on-update / `synchronize` behavior and any interaction with autogen — before it is relied on. This is the one
  item to validate at build time; it does not change the decision.
- **preStop sleep over-sizing.** A native `sleep` action can keep counting after PID 1 exits (kubernetes#134338); keep the
  default small (10s) and well under the grace period.
- **App contract gap (not platform-solvable).** If an app hard-exits on SIGTERM mid-request, in-flight work still drops —
  preStop only buys the endpoint-propagation window. **Long-lived connections** (websockets, gRPC streams, long polls) are
  not covered by a preStop sleep and need app-level connection-age limits / GOAWAY; this is a documented known limitation,
  out of scope for the default tier.

## Alternatives considered

- **PDBs generated by the Crossplane `XEnvironment` Composition.** The first instinct, rejected: the Composition's
  per-service axis has no matching pod label, so it cannot build a correct selector (D3). A per-*product* PDB it *could*
  build would lump all services into one budget and break under multi-service.
- **Inject everything via the scaffolder only.** Visible and teachable, but only covers new products, drifts, and is
  deletable. Kept as the *teaching* surface (D6), not the *enforcement* surface.
- **Mutate `replicas` to a floor.** Rejected — fights the HPA and the prod overlay; the floor is validated, not mutated
  (D4).
- **Do nothing until ADR-056.** Rejected — it inverts the dependency. Canary on top of a connection-dropping base is
  polish over a hole.

## Related

- [ADR-056](056-progressive-delivery-and-safe-rollback.md) — Progressive delivery & safe rollback; the **release-safety**
  domain this ADR is the foundation for.
- [ADR-054](054-platform-resilience-and-business-continuity.md) — Resilience & business continuity; the SLO/error-budget
  contract that the k6-through-disruption test ultimately feeds.
- [ADR-078](078-cluster-elasticity-karpenter.md) — Karpenter elasticity; the source of the live voluntary-disruption
  pressure (and the NodePool `terminationGracePeriod` backstop, D5). Note the NodePool-budget vs Pod-PDB distinction.
- [ADR-014](014-kyverno-as-policy-engine.md) — the Kyverno engine and the mutate/validate/generate machinery this extends.
- [ADR-017](017-gateway-api-over-ingress.md) / Cilium CNI ([ADR-008](008-cilium-as-cross-cloud-cni.md)) — the
  Gateway/Envoy + terminating-endpoint datapath whose default behavior D2 pairs with.
- [ADR-067](067-idp-domain-model.md) — the Team→Product→Service model; multi-service is the case the workload-derived PDB
  selector handles by construction.
