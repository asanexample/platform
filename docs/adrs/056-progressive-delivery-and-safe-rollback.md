# ADR-056: Progressive Delivery & Safe Rollback

**Date:** 2026-06-04 (amended 2026-06-26)

**Status:** Accepted — Phase 1 built + applied (both clusters); Phase 2 mechanics proven (see as-built). Adds health-gated, automatically-reversible rollouts on top of the
existing GitOps delivery ([ADR-021](021-argocd-for-gitops.md)) and PR preview environments
([ADR-032](032-pr-preview-environments.md)), and is the **release-safety half of zero-downtime deployment** —
the foundation (traffic correctness during the pod lifecycle) is [ADR-085](085-workload-availability-graceful-disruption-defaults.md).
Consumes the SLO/error-budget contract from [ADR-054](054-platform-resilience-and-business-continuity.md), the
separation-of-duties from [ADR-040](040-platform-engineer-access-model.md)/[ADR-049](049-tenant-model-team-tenant-zone.md),
and the Gateway API ([ADR-017](017-gateway-api-over-ingress.md)) for traffic shaping.

> **Amendment (2026-06-26).** Two changes from the original prod-only strategy, after the design research that
> followed ADR-085 (the zero-downtime *foundation* this layers on):
>
> 1. **Argo Rollouts is the model for ALL environment workloads, every stage** — not just prod. The tier decides
>    the *strategy* (lower envs auto-promote to dogfood the path; prod gates on metrics), never *whether* to use
>    a Rollout. This is the platform's "one road" ethos ([ADR-081](081-platform-service-delivery.md)) applied to
>    delivery: prod is never the first place a Rollout runs.
> 2. Workloads are **direct `spec.template` Rollouts** (the Rollout owns the pod template; no Deployment), which
>    makes `Rollout` a first-class pod controller the admission layer must understand (D2).
>
> D1–D8 reflect this; the integration design + phased rollout live in `docs/plans/056-progressive-delivery.md`.

## Context

Delivery is GitOps (ArgoCD) with ApplicationSet PR previews — strong for the inner loop. But a rollout is a
**plain ArgoCD sync**: the new version replaces the old with no canary, no health-gated promotion, and **no
automatic rollback**. ADR-085 made a deploy *non-dropping* (old pods drain, replicas spread, PDBs protect) —
but a plain sync still swaps old→new at **100% of traffic instantly**, so a broken *version* is an outage no
matter how cleanly the old pods drained. Domain 1 (traffic correctness) is done; domain 2 (release safety —
catch a bad version before it reaches everyone) is this ADR. A bad deploy is currently caught by humans, after
impact; regulated prod needs progressive, auto-reverted rollouts with separation of duties; and the per-tier
**error budgets** (ADR-054) have no rollout to gate.

## Decision

### D1 — Argo Rollouts for every environment workload, all stages

Every environment workload is an Argo `Rollout` (canary or blue-green), on **every stage** (dev → prod).
Rollouts integrate natively with ArgoCD and the Gateway API the platform already runs. Analysis steps query the
observability stack (Mimir) as **health gates**, with **automatic rollback on breach**.

### D2 — Direct-template Rollouts; the admission layer treats `Rollout` as a first-class pod controller

The Rollout owns `spec.template` (no Deployment object). This is the clean single-object model, but it makes
the **ADR-085 availability policies first-class consumers of the `Rollout` kind** — the load-bearing coupling:

- **Controller-kind policies must learn `Rollout`.** `generate-workload-pdb`, `mutate-topology-spread`, and
  `require-prod-replica-floor` match `Deployment`/`StatefulSet` *by kind* and **silently no-op on a Rollout**
  until `argoproj.io/v1alpha1/Rollout` is added to their `match.kinds`. The selector/replicas paths are
  identical, so each extension is small (plus one fix: `matchLabelKeys: pod-template-hash` →
  `rollouts-pod-template-hash`, since Rollout pods carry that label). Same for `disallow-default-namespace`.
- **Pod-level policies keep protecting pods regardless.** securityContext / preStop / image-registry / cosign /
  probes match `Pod`, and a Rollout's ReplicaSets are already a Kyverno autogen target — so defaults still land
  on the pods. We *lose* only admission-time fast-fail on the Rollout object itself (a non-compliant Rollout is
  admitted, then fails as a stuck rollout). Optionally add `Rollout` to those rules' autogen for fast-fail.
- **CRD before policy.** A Kyverno rule naming a kind whose CRD is absent fails to create (Kyverno #7839), so
  the Argo Rollouts CRDs must install **before** the `policy` unit — a DAG ordering constraint (D7).
- **ArgoCD AppProject whitelist** (`namespaceResourceWhitelist`) must add `argoproj.io/Rollout` (+
  `AnalysisTemplate`/`AnalysisRun`) or ArgoCD refuses to sync the Rollout.

### D3 — The rollout *strategy* is a tier/stage property, not per-app guesswork

One manifest shape; the strategy differs by stage:

- **dev / test / preprod** — a **trivial auto-promoting canary** (`setWeight: 100`, no analysis, `maxSurge: 1`,
  `trafficRouting` optional). Purpose: dogfood the Rollout object, admission, and (optionally) traffic plumbing
  at near-zero cost — *not* to gate on metrics (which lower envs can't do; D5).
- **prod / standard** — stepped canary with **metric gates** (D5) and automatic rollback.
- **prod / regulated** — + a **manual approval gate** (deployer ≠ approver, ADR-049) + audit.

### D4 — L7 canary via Gateway API weighted HTTPRoute (Cilium Gateway), no mesh

Traffic splitting uses the Argo Rollouts **Gateway API trafficrouter plugin**, which edits `weight` on the
HTTPRoute `backendRefs` (stable vs canary). Cilium 1.19 supports weighted backendRefs. Each canary-ed app needs
a **stable + canary Service** (both ClusterIP) as weighted backends of its single existing HTTPRoute — the
hostname is unchanged, so `restrict-route-hostnames` is not triggered. Lower envs may omit `trafficRouting`
(basic replica-based canary). A mesh is revisited only for *east-west* canary ([ADR-057](057-service-identity-and-east-west-zero-trust.md)).

### D5 — Metric gates use Beyla RED metrics; the constraint is the Mimir READ path, not prod-ness

There are no per-app SLOs yet (only a control-plane apiserver SLO), so the default canary gate is **Beyla RED
metrics** — auto-emitted per workload, no instrumentation. AnalysisTemplates query Mimir with an
`X-Scope-OrgID: <cluster-tenant>` header, and the rollouts-controller namespace needs a **NetworkPolicy** to
reach `mimir-gateway` (the `observability` namespace is default-deny). The real prerequisite is that **the
rollout's cluster can READ Mimir**: on the **hub** (platform) Mimir is local, so metric gates work there today;
on a **spoke** (preprod, and any future prod) Mimir is write-only (remote-write up, no read down), so a
spoke→hub Mimir **read route** must be wired first — a small networking task, *not* a new cluster. So metric
gates are gated on that read path, not on prod-ness; lower envs auto-promote without gates regardless (D3).
(Per-app Sloth SLOs can be authored later to replace/augment the Beyla gate.)

### D6 — Error budgets gate change velocity

The tier availability SLO (ADR-054) defines the budget; **budget exhaustion freezes non-critical rollouts**
until it recovers.

### D7 — Argo Rollouts is a platform addon

A new `argo-rollouts` module + unit installs the controller, CRDs, and the Gateway-API trafficrouter plugin
(with its extra HTTPRoute RBAC). DAG slot: after `gateway` (the plugin needs the shared Gateway), **before**
`policy` (CRD-before-policy, D2) and `argocd-apps` (CRDs before any tenant Rollout is synced).

### D8 — PDB-during-canary

The ADR-085 auto-generated PDB selects on the workload's `matchLabels`, which **both** stable and canary
ReplicaSets' pods carry — so it is a single combined budget across versions (Argo doesn't do per-RS PDBs). Keep
`maxUnavailable` an **integer** (percentage is unreliable for Rollout-owned pools) and pair it with `maxSurge ≥
1` so a canary always has headroom and can't deadlock against the budget during a concurrent Karpenter
consolidation.

## Alternatives considered

- **`workloadRef` to a Deployment** (Rollout references a scaled-to-0 Deployment). Keeps the ADR-085
  controller-kind policies firing on the Deployment — but breaks `require-prod-replica-floor` (replicas move to
  the Rollout), means two objects + a confusing scaled-to-0 Deployment, and carries an initial-creation race
  (argo-rollouts #4065). Rejected: the policy work it saves is small and we own it, and direct is the cleaner
  first-class model.
- **Rollouts for prod only** (the original strategy). Rejected: prod would be the first place a Rollout ever
  runs — the opposite of dogfooding; and it re-introduces a delivery split this platform works to erase.
- **Flagger.** Comparable, but Argo Rollouts is closer to the existing ArgoCD + Gateway API stack. Rejected on
  fit, not merit.
- **Manual canary via two ArgoCD apps + weighted routes.** No automated analysis or rollback — status quo with
  extra steps. Rejected.

## Consequences

### Positive

- **Release safety to match the ADR-085 traffic safety** — a bad version is caught and auto-reverted before it
  reaches everyone, with auditable approval gates for regulated prod.
- **One delivery shape everywhere** — the Rollout path, admission, and traffic plumbing are exercised in every
  env, so prod is never the first run.

### Negative / cost

- **Touches the ADR-085 policies + the scaffolder + the AppProject** (D2) — a deliberate, coordinated migration,
  not a flag-flip. Two silent traps: the kustomize `replicas:` transformer doesn't target `Rollout`, and the
  `matchLabelKeys` label key changes.
- **Canary needs a stable+canary Service + weighted route**, which must be reconciled with the existing
  PR-preview `name-reference.yaml` / `preview-routing-check` machinery.

### Risks

- **Cilium 1.19 + the Gateway-API plugin** (v0.15, pre-1.0, lightly trodden together) — verify weighted
  backendRefs incl. weight-0/cutover + cross-namespace route reconcile with a live preprod check before
  standardizing.
- **Kyverno autogen for `Rollout`** if we pursue Rollout-template fast-fail — missing-CRD breaks policy
  creation, and mixed standard+custom autogen is buggy (#7446); keep any Rollout autogen in its own rule.
- **Metric gates need the spoke→hub Mimir read path** (D5) — not a new cluster. The Gateway canary itself works
  on preprod today (Cilium honors weighted backendRefs); only the *metric-gated* half waits on wiring a
  preprod→hub Mimir read route (or runs on the hub for platform-team Rollouts). Phase 1 delivers
  Rollouts-everywhere with the trivial strategy; Phase 2 adds the Gateway canary (preprod-ready) then analysis.

## Implementation status & learnings (as-built)

*2026-06-26 (#851–#861).*

**Built + applied + verified (both clusters):**

- **Phase 1 (Rollouts everywhere, trivial strategy).** Every environment workload is a direct-template Argo
  `Rollout` (not Deployment). `argo-rollouts` module + unit installs the controller/CRDs; the ADR-085
  availability policies (PDB-generate, topology-spread, replica-floor) were made `Rollout`-aware
  (`enable_rollout_kind`); the scaffolder emits a Rollout; `app-alpha-shop` was migrated and a deploy verified
  **zero-drop under load** (k6, 0/4501 failed). The trivial `setWeight: 100` + `maxSurge:1/maxUnavailable:0`
  strategy is the safe default — auto-promote, no traffic split — so prod is never the first place a Rollout runs.
- **Phase 2 mechanics (proven on preprod, spikes torn down).** The **Gateway-API traffic-router plugin** is
  installed + durable (D4): a real canary drove weighted HTTPRoute `backendRefs` and **Cilium honored them**
  (50/50 split, promoted). **Both strategies** work on the same controller: **canary** (weighted, needs the
  plugin) and **blue/green** (D1) — the latter is a pure Service-selector swap, needs **no** plugin, and gives a
  *stronger* guarantee (a bad version gets **zero** prod traffic vs canary's brief slice). A **health-gated
  auto-rollback** was proven: a version that is *up but serving wrong content* (which readiness can't catch) fails
  the analysis gate and auto-reverts.

**Corrections / integration prerequisites the design under-weighted.** The spikes ran in an *unenforced* namespace
and *outside* ArgoCD; making this the GitOps default for tenant apps requires three things the original D-points
didn't call out — all because Kyverno (ADR-014) and ArgoCD selfHeal (ADR-021) impose constraints the spike bypassed:

1. **A Job-provider AnalysisTemplate does NOT work in an enforced environment namespace** — Kyverno
   `restrict-images` denies the analysis Job's image (it isn't team-ECR scoped). Use a **web/Prometheus
   provider** (runs in the controller, creates no Job pod), not a `job` provider.
2. **A web/Mimir-provider gate needs a NetworkPolicy** — the rollouts-controller→target reach (canary Service, or
   the default-deny `observability` namespace for Mimir). This belongs to the Environment Composition (env
   namespace CNPs) / the obs module, not the app manifests.
3. **ArgoCD `selfHeal` fights the plugin** — the tenant ApplicationSet runs `selfHeal: true`, so the plugin's
   HTTPRoute weight rewrites are reverted mid-canary unless the Application **`ignoreDifferences`** the
   `backendRefs[].weight` path. Required for any selfHeal'd canary.

Net: D5's metric gate is gated on the **Mimir read path** (a spoke is write-only to the hub Mimir, #860) **and**
the controller→target NetworkPolicy — not on a prod cluster. The traffic-shaping canary/blue-green shapes work in
enforced namespaces today *given* the ArgoCD `ignoreDifferences`.

*2026-06-27 (#871–#892, alpha-shop #6–#10) — the durable wiring, the metric gate, and the live proof.*

- **Per-workload strategy + ArgoCD `ignoreDifferences`** shipped (#871). A scaffolder `deployStrategy` (canary |
  blue/green) shapes only the prod overlay (base unchanged → dev/preview stay fast, preview-safe). The tenant
  Application `ignoreDifferences` the Service `.spec.selector` (rollouts-pod-template-hash) + HTTPRoute
  `backendRefs[].weight`.
- **CORRECTION to integration prereq #3 above:** `ignoreDifferences` ALONE is insufficient — it only hides the
  fields from the *diff*; a sync triggered by any *other* change still overwrites them. The tenant Application
  also needs **`RespectIgnoreDifferences=true`** in `syncOptions`. Caught in prod (a weight patch went OutOfSync
  and was reverted) — the spikes couldn't surface it. Two more corrections from the same live validation: an
  applied-but-**unmerged** module change gets clobbered by the registry-reconcile re-applying from `main` (merge,
  don't just apply); and Argo Rollouts **fast-tracks a rollback** to an in-history revision (skips the canary
  steps) — re-trigger a canary with a *fresh* digest. Prod's separation-of-duties gate correctly **blocks a solo
  maintainer from deploying to prod** (needs a non-author approval) — verified, working as designed.
- **W8c — the metric gate is BUILT + PROVEN LIVE.** The spoke→hub Mimir **read path** is an opt-in `query_tenants`
  on the `observability-mimir` `spoke_ingest`: it adds a `/prometheus` rule to the spoke's HTTPRoute,
  **force-setting the same tenant header** — so a spoke queries only its own metrics (no new exposure; reuses the
  TGW + internal NLB + Gateway + CNP; no extra netpol needed — correcting prereq #2 for the *cross-cluster* case).
  The prod canary runs a **background AnalysisRun** (Prometheus provider → that read path) over the Beyla RED
  success rate, auto-rolling-back below 0.95. Resolves D5 — the gate is gated on the *read path*, not a prod
  cluster (and the endpoint is the prod stage's Mimir; prod runs on preprod today, repoint when a prod cluster
  lands).
- **Proven end-to-end on a real prod app (alpha-shop):** a healthy deploy canaried 25→50→100% while the gate
  queried Mimir (rate 1.0) and **promoted**; a forced-fail deploy canaried to 25%, the gate assessed **Failed**,
  and the rollout **auto-aborted and rolled back** (traffic snapped to stable, zero sustained bad-version
  traffic). Both `strategy.canary` and `strategy.blueGreen` proven; Kyverno admits the signed canary image in the
  enforced prod namespace throughout.

**Remaining (future):** **W9** tier-keyed *depth* — the binary (prod = gated canary, lower stages = trivial) is
done; finer per-stage tuning (e.g. a staging canary without the gate) is optional. **Phase 3 / D6** — the
regulated manual-approval gate (a native Rollout `pause: {}` + RBAC for deployer ≠ approver) and the error-budget
freeze (needs per-app SLOs authored in `observability-slo` first). These are fresh efforts, not tail work.

## Related

- [ADR-085](085-workload-availability-graceful-disruption-defaults.md) — the zero-downtime *foundation* (domain
  1) this is the release-safety half of; its availability policies are the load-bearing coupling (D2).
- [ADR-069](069-delivery-source-of-truth-product-environment.md) / [ADR-071](071-digest-promotion-via-control-plane.md)
  — the Release/digest delivery the Rollout strategy plugs into.
- [ADR-054](054-platform-resilience-and-business-continuity.md) — the SLO/error-budget contract (D5/D6).
- [ADR-017](017-gateway-api-over-ingress.md) — the Cilium Gateway weighted routing (D4).
- [ADR-014](014-kyverno-as-policy-engine.md) — the admission layer that must learn `Rollout` (D2).
</content>
