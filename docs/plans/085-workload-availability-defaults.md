# Implementation Plan — Workload Availability Defaults (ADR-085)

> **Status: DELIVERED — applied live on both clusters; replica-floor flipped to Enforce 2026-06-27 (#934). Retained for history.**

Companion to [ADR-085](../adrs/085-workload-availability-graceful-disruption-defaults.md). Builds the foundational
zero-downtime tier across the four injection points: the Kyverno **mutate** (graceful draining), a Kyverno **generate**
(PDBs), a Kyverno **validate** (replica floor), and the Karpenter **NodePool** (disruption backstop) — plus the scaffolder
surface and the offline + live verification.

## Refinement vs. the ADR (read first)

Detailing the work surfaced one correction to ADR-085 §D2: **`topologySpreadConstraints` cannot be injected by the generic
`mutate-pod-defaults` patch.** A spread constraint's `labelSelector` must match the *workload's own* pods, and a static
strategic-merge mutate has no per-workload label data — a constraint with no/empty selector silently spreads nothing. So:

- **`preStop` + `terminationGracePeriodSeconds`** stay in the mutate (genuinely generic, no per-workload data needed).
- **`topologySpreadConstraints`** moves to the **scaffolder skeleton** (where the app's `app:` label is known and a real
  `labelSelector` can be written statically). A Kyverno-derived version for retroactive/hand-written coverage is a
  **follow-on spike** that reuses W2's selector-from-workload technique.

ADR-085 §D2 is **corrected directly in this same PR** (the ADR is still Proposed/unmerged, so the reviewer sees the
accurate version — no dated amendment block needed for an unmerged record).

## Work items

Ordered by dependency. **W0 is a gate** — it de-risks the two novel Kyverno techniques before any of the dependent work.

### W0 — Spike: prove the novel Kyverno techniques offline (GATE)

The two things the platform hasn't done before, both provable in the existing offline harness
(`infra/modules/policy/.kyverno-tests/`, `helm template` → `kyverno test`/`kyverno apply`):

1. **`generate` with a selector copied from the trigger workload** — does
   `selector.matchLabels: "{{ request.object.spec.selector.matchLabels }}"` render a *map* correctly into the generated
   PDB, and does it behave under `synchronize: true` on update? (W2's crux.)
2. **Native `preStop.sleep` injection under autogen** — confirm the mutate relocates cleanly to `spec.template.spec` for
   Deployment/StatefulSet (the existing smoke-check already exercises autogen; extend it).

**Exit criteria:** a rendered PDB with the correct `maxUnavailable: 1` + workload-matched selector, and a mutated
Deployment carrying `preStop`/`terminationGracePeriodSeconds`, both asserted in `.kyverno-tests`. If (1) proves brittle in
the CLI, fall back to a rendered-manifest assertion + a post-apply live smoke test (documented in the harness). **Blocks
W2; informs the topology-spread follow-on.**

### W1 — D2 draining defaults: extend `mutate-pod-defaults`

**File:** `infra/modules/policy/policies-chart/templates/mutate-pod-defaults.yaml` — add to the existing single
`add-pod-defaults` patch (keeps the "one patch resolves under autogen" property):

```yaml
spec:
  +(automountServiceAccountToken): false
  +(terminationGracePeriodSeconds): 30          # NEW — pod level
  containers:
    - (name): "?*"
      securityContext: { … existing … }
      +(lifecycle):                              # NEW — per-container, native SleepAction (GA on EKS 1.35)
        preStop:
          sleep:
            seconds: 10
  initContainers:
    - (name): "?*"
      securityContext: { … existing … }          # no lifecycle on initContainers (meaningless)
```

Update the policy `description` annotation. Mutate already `failurePolicy: Ignore` (fails open) → **zero admission
risk**. **Test:** extend the `run.sh` mutation smoke-check — raise the success-count threshold and `grep` the captured
output for `terminationGracePeriodSeconds` and `preStop` (the existing grep-assertion style; declarative
`patchedResource` asserts are intentionally avoided here).

### W2 — D3 PodDisruptionBudget via `generate` (depends on W0)

**New file:** `infra/modules/policy/policies-chart/templates/generate-pdb.yaml` — a ClusterPolicy:

```yaml
spec:
  rules:
    - name: generate-workload-pdb
      match:
        any:
          - resources:
              kinds: [Deployment, StatefulSet]
              {{- include "kpp.environmentNamespaceSelector" . | nindent 14 }}
      generate:
        apiVersion: policy/v1
        kind: PodDisruptionBudget
        name: "{{ request.object.metadata.name }}-pdb"
        namespace: "{{ request.object.metadata.namespace }}"
        synchronize: true                          # reconciles back if deleted/edited
        data:
          spec:
            maxUnavailable: 1                       # drain-safe by construction
            selector:
              matchLabels: "{{ request.object.spec.selector.matchLabels }}"
```

Notes:

- `maxUnavailable: 1` on a 1-replica workload still permits the single eviction → never blocks a drain; protection kicks
  in once replicas ≥ 2 (W3).
- Always-generate (no replica precondition) is fine and simplest. **Build decision:** whether to skip when the workload
  ships its own PDB — recommended *not* to special-case (uniquely-named `<name>-pdb`; if an app ships its own, both apply
  and the most restrictive wins, both being `maxUnavailable`-style). Document in `authoring-k8s-workloads`.
- **Test:** the W0 generate assertion, promoted into the standing harness.

### W3 — D4 replica floor: validate `replicas ≥ 2`, prod-stage only

**New rule** (own template, e.g. `availability-validate.yaml`, or fold into `pod-hardening.yaml`): match
`Deployment`/`StatefulSet` whose namespace matches the **`*-prod`** glob (the existing `namespace-governance` pattern —
there is no per-stage chart value), validate `spec.replicas >= 2`.

- Use the **per-rule `validate.failureAction`** field (Kyverno 1.18 — *not* the deprecated `spec.validationFailureAction`)
  so it honors the cluster's audit/enforce knob.
- **Ship Audit-first, then flip to Enforce** (the platform's audit-first convention) — see Rollout.
- **HPA interaction:** validating `spec.replicas >= 2` is compatible with an HPA-managed Deployment (a `replicas: 2` floor
  coexists with HPA scaling above `minReplicas`). Pair with the recommendation that prod HPAs set `minReplicas >= 2`.
  **Never mutate replicas** (would fight HPA + the prod overlay).
- **Test:** declarative `kyverno test` result assertions — `pass` for `replicas: 2`, `fail` for `replicas: 1` in a
  `*-prod` namespace, `skip`/`pass` in non-prod (standard validate-test pattern).

### W4 — D5 Karpenter backstop: NodePool `terminationGracePeriod`

**File:** `infra/modules/aws/karpenter/charts/nodepool/templates/nodepool.yaml` — add under `spec.template.spec`:

```yaml
  template:
    spec:
      terminationGracePeriod: {{ .Values.terminationGracePeriod }}   # NEW
      nodeClassRef: { … }
```

Plumb the value: chart `values.yaml` → module `variables.tf` (default e.g. **`24h`**) → live unit inputs. This bounds how
long *any* blocking PDB or `karpenter.sh/do-not-disrupt` pod can stall voluntary disruption before Karpenter forcibly
drains — a safety bound (not an SLA) that makes the permissive self-service PDB default safe even against a bad
hand-written PDB. Independent of W0–W3; can ship anytime. **Test:** `helm template` renders the field; Terratest plan-only
if the karpenter module has a fixture.

### W5 — Scaffolder surface (the teaching layer)

**File:** `scaffolder/templates/new-product/skeleton/k8s/base/deployment.yaml`:

- Add visible `terminationGracePeriodSeconds: 30` (pod) and container `lifecycle.preStop.sleep.seconds: 10` — explicit
  copies of the W1 defaults (mutate is add-if-absent → no conflict).
- Add `topologySpreadConstraints` with a **real `labelSelector`** matching the skeleton's known
  `app: app-${{ values.team }}-${{ values.product }}` + `matchLabelKeys: [pod-template-hash]`, `whenUnsatisfiable:
  ScheduleAnyway`, across `topology.kubernetes.io/zone` and `kubernetes.io/hostname`. **This is topology-spread's primary
  home** (labels known statically) per the refinement above.
- **Do not** ship a PDB in the skeleton — W2's generate rule is the source of truth; a skeleton PDB would duplicate it.
  Document the auto-generated PDB in `authoring-k8s-workloads` instead.

The base already has `replicas: 2` and the prod overlay bumps to 3, so W3 passes for scaffolded apps out of the box.

### W6 — Docs

- ADR-085 D2 already corrected (the topology-spread refinement, this PR).
- `authoring-k8s-workloads` skill: the app **SIGTERM contract** (preStop buys the propagation window; the app must drain
  in-flight on SIGTERM), the **auto-generated PDB**, the **long-lived-connection** caveat, and the prod `replicas ≥ 2` /
  HPA-`minReplicas` note.
- `kyverno-policy-authoring` skill + `infra/modules/policy/README.md`: the new generate + validate rules.

## Verification (the acceptance test)

Per ADR-085 §Verification — the only honest test is observed, not asserted. After applying to **preprod** first:

A **k6** load test (already in the LGTM+P stack) driving steady traffic through the Gateway while we trigger, in turn:

1. `kubectl rollout restart` of a 2-replica app,
2. a Karpenter consolidation (cordon + drain the node hosting a replica),
3. a `platctl` park/unpark cycle.

**Pass = zero non-2xx and zero connection resets across all three**, observed in Grafana/Mimir. This is the gate before
flipping W3 to Enforce and before applying to platform.

## Rollout & sequencing

| Phase | Ships | Risk posture |
|---|---|---|
| 1 | **W0** spike (offline only) | none — no cluster change |
| 2 | **W1** mutate + **W5** scaffolder + **W4** Karpenter backstop | mutate fails open; scaffolder is new-product only; backstop is a wide bound |
| 3 | **W2** generate PDB (after W0 passes) | PDBs are `maxUnavailable: 1` (drain-safe) + W4 backstop |
| 4 | **W3** validate `replicas ≥ 2` as **Audit** | observe-only |
| 5 | **k6 verification on preprod** → flip **W3 to Enforce** → apply to **platform** | gated on observed zero-downtime |

Suggested PR grouping: **PR-A** = W0+W1+W5 (draining + scaffolder, test-backed); **PR-B** = W2 (PDB generate);
**PR-C** = W3 (validate, Audit) + W4 (Karpenter); **PR-D** = flip W3 Enforce + verification notes. W6 docs ride the
relevant PR.

**Apply notes:** policy-module and karpenter changes apply via their live units with `AWS_PROFILE=management`
(PlatformDeployer), per the `apply-and-destroy` skill, **preprod before platform**. **Never apply from a worktree** — the
absolute-path `null_resource` trigger trap; apply from the main repo root.

## Open decisions (resolve at build)

- W2: skip-if-PDB-exists vs. always-generate (recommended: always-generate, documented).
- W4: the exact `terminationGracePeriod` default (`24h` proposed) and whether to vary it by `cost_profile`/cluster.
- Topology-spread follow-on: ship the Kyverno-derived version (reusing W2's technique) or leave spread as
  scaffolder-only for now.
</content>
