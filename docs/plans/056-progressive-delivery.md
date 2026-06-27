# Implementation Plan — Progressive Delivery (ADR-056)

Companion to [ADR-056](../adrs/056-progressive-delivery-and-safe-rollback.md). Builds Argo Rollouts as the
delivery model for **every** environment workload (direct `spec.template` Rollouts), tier-keyed strategy,
metric-gated canary for prod. The release-safety half of zero-downtime deploy; the foundation is
[ADR-085](../adrs/085-workload-availability-graceful-disruption-defaults.md).

Grounded in the design research — the standout finding is the **ADR-085 coupling** (the availability policies
match `Deployment` by kind and silently no-op on a `Rollout`), so the policy extension and the install ordering
are load-bearing, not afterthoughts.

## Phase 0 — De-risk (spike, gates the rest)

The two pre-1.0 / lightly-trodden integrations, proven in **preprod** before committing the migration:

1. **Cilium 1.19 + Gateway-API trafficrouter plugin** — install Argo Rollouts + the plugin, stand up one app
   with a stable+canary Service and a weighted HTTPRoute, and confirm Cilium honors `weight` end to end:
   stepped weights, **weight-0 / cutover**, and **cross-namespace** route↔Gateway reconcile (the shared Gateway
   is in `default`, tenant routes elsewhere). **Exit:** a manual `setWeight` moves real traffic; weight-0 works.
2. **Kyverno + direct `Rollout`** — apply a direct-template `Rollout` to an env namespace and confirm: pod-level
   policies still land on its pods (via ReplicaSet autogen), and an extended controller-kind policy (e.g.
   PDB-generate with `Rollout` added) fires. **Exit:** the policy plumbing is proven before the full extension.

If (1) fails, fall back to basic replica-based canary (no Gateway weighting) and revisit; (1) is the only thing
that could change the D4 approach.

## Phase 1 — Rollouts everywhere, trivial strategy (the migration)

Make every workload a `Rollout` with an auto-promoting (no-analysis) strategy — dogfood the path with no canary
cost. No metric gates yet.

- **W1 — install** (`infra/modules/argo-rollouts` + live units, both clusters): the controller + CRDs + the
  Gateway-API plugin + RBAC. DAG slot: after `gateway`, **before** `policy` and `argocd-apps` (CRD-before-policy).
  Add to the `apply-and-destroy` / `platctl` ordering.
- **W2 — extend the ADR-085 controller-kind policies to `Rollout`** (`infra/modules/policy`): add
  `argoproj.io/v1alpha1/Rollout` to `match.kinds` on `generate-workload-pdb` (+ `rollouts` in the
  background-controller RBAC for `generateExisting`), `mutate-topology-spread` (+ `matchLabelKeys` →
  `rollouts-pod-template-hash`, likely a Rollout-specific rule variant since the key differs by kind),
  `require-prod-replica-floor`, and `disallow-default-namespace`. Extend the offline kyverno-test harness with a
  `Rollout` fixture asserting each fires. (Optional: add `Rollout` to the Pod-policy autogen for admission-time
  fast-fail — its own rule, to dodge Kyverno #7446.)
- **W3 — AppProject whitelist** (`infra/modules/argocd-apps/delivery.tf` + `agents.tf`): add
  `argoproj.io/Rollout` (+ `AnalysisTemplate`/`AnalysisRun`) to `namespaceResourceWhitelist`, or ArgoCD won't
  sync.
- **W4 — scaffolder** (`scaffolder/.../k8s/`): `base/deployment.yaml` → `rollout.yaml` (Deployment→Rollout,
  add a `strategy.canary` with `setWeight: 100`/`maxSurge: 1`); fix the two silent traps — the kustomize
  `replicas:` transformer needs a `configurations:` entry for `argoproj.io/Rollout` (else per-stage counts
  vanish), and `matchLabelKeys` → `rollouts-pod-template-hash`. Update overlays' `kind:` in patches.
- **W5 — migrate the reference apps** (alpha-shop etc.) Deployment→Rollout; verify on preprod a deploy still
  rolls (k6 zero-drop, reusing the ADR-085 test), the PDB/topology/replica-floor still apply, and the trivial
  canary auto-promotes.
- **W6 — docs**: `authoring-k8s-workloads` (workloads are now `Rollout`s; what the strategy block looks like;
  what's still auto-handled), the `argocd-app-delivery` skill, and a migration note.

**Phase 1 exit:** every preprod workload is a Rollout, deploys are zero-drop, all ADR-085 guarantees still hold.

## Phase 2 — Gateway canary + metric gates

The real progressive delivery, on the path Phase 1 laid. **Not gated on a prod cluster** — the two halves have
different prerequisites, and neither is prod-ness:

- **W7 — Gateway canary wiring (no metric/cluster dependency — buildable on preprod NOW).** The Argo Rollouts
  Gateway-API traffic-router plugin (+ its HTTPRoute RBAC) on the existing `argo-rollouts` controller; per app a
  stable+canary Service pair + weighted HTTPRoute; reconcile with the PR-preview `name-reference.yaml` /
  `preview-routing-check` so the second backendRef isn't mis-rewritten. Cilium honors weighted backendRefs
  (Phase-0 proven), so a real stepped canary can be validated on **preprod** immediately. **De-risk first** (the
  plugin is pre-1.0 and the Cilium+plugin combo is lightly trodden): a spike running one canary Rollout end to
  end before building the module change.
- **W8 — metric-gated analysis (gated on the Mimir READ path, not prod).** A default `AnalysisTemplate` (Beyla
  RED metrics — success-rate + p99 latency) querying Mimir with the `X-Scope-OrgID` header; a **NetworkPolicy**
  letting the rollouts-controller namespace reach `mimir-gateway` (obs ns is default-deny). The real constraint:
  the rollout's cluster must be able to *read* Mimir. On the **hub** (platform) that's local — metric gates work
  there today. On a **spoke** (preprod, and any future prod) Mimir is write-only, so a spoke→hub Mimir **read
  route** must be wired first (a small networking task, not a new cluster). So W8 lands either by (a) wiring the
  preprod→hub read path, or (b) validating on the hub for platform-team Rollouts.
- **W9 — tier-keyed strategy**: the canary strategy becomes a per-stage property (dev/preprod trivial →
  prod/standard stepped+gated). Where this is templated (scaffolder overlays vs the Composition) is the open
  design choice for this phase.

## Phase 3 — Governance gates

- **W10 — regulated manual-approval gate** (deployer ≠ approver, ADR-049) + audit, for `prod/regulated`.
- **W11 — error-budget freeze** (ADR-054): budget exhaustion blocks non-critical rollouts.

## Open decisions (resolve during the phases)

- Where the per-stage strategy is templated — scaffolder overlays, or generated by the Crossplane Composition
  (the latter centralizes it but couples delivery shape to the provisioner).
- Whether to add `Rollout` to the Pod-policy autogen (fast-fail) or rely on ReplicaSet-autogen pod coverage.
- Per-app Sloth SLOs vs the generic Beyla RED gate as the default analysis metric.
- Blue-green vs canary as the default strategy for stateful / non-HTTP workloads.

## Rollout & sequencing

Phase 0 (preprod spike) → Phase 1 (migrate, preprod then platform; the trivial strategy is safe — auto-promote,
no traffic split) → Phase 2 Gateway canary on preprod now (W7), metric gates once the Mimir read path is wired
(W8) → Phase 3. Apply per the `apply-and-destroy` rules
(`AWS_PROFILE=management`, plan-check `0 to destroy`, preprod before platform). The install (W1) is a new unit
in the DAG; the policy extension (W2) and scaffolder (W4) are the coupling-sensitive pieces — land them with the
migration, not before workloads are Rollouts.
</content>
