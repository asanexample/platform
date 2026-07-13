# ADR-103: SLO Materialization — environment-derived Sloth CRs, off the provisioning path

**Date:** 2026-07-12

**Status:** Proposed — target architecture. Supersedes the current Terragrunt registry-derivation (`app_slos` in the `mimir` live unit) as the mechanism for per-app SLOs. No code shipped by this ADR.

## Context

Per-app availability + latency SLOs today are derived at `terragrunt apply` time by the `mimir` unit: it globs `gitops/environments/**/*.yaml` (every environment, any stage), builds raw multi-window burn-rate PromQL from `templates/app-slo-rules.yaml.tftpl`, and pushes it into the `app-slos` Mimir ruler namespace via a `mimirtool rules sync` CronJob (ADR-056 W11). It works, but the *mechanism* has four problems:

1. **Lifecycle seam.** SLOs materialize on the `mimir` unit's apply cadence, not with the environment. A new `XEnvironment` can be reconciled and serving while it has no SLO; a deleted one can leave orphan rules until the next apply.
2. **No self-healing / GC.** Nothing reconciles drift or cleans up removed environments.
3. **Bespoke, duplicated downstream.** Raw PromQL + `mimirtool` runs *parallel* to the Sloth `PrometheusServiceLevel` path used for hand-authored platform SLOs (e.g. kube-apiserver). Two systems doing the same job.
4. **Objective hard-coded.** A fixed 99.9%/99% in the template, with no tier/per-service policy.

The obvious "fix" — folding SLO reconciliation into the **XEnvironment Composition** — is rejected here (see Alternatives): it puts observability config on the environment *provisioning critical path*, and mismatches the delivery mechanism.

## Decision

Materialize SLOs as **environment-derived Sloth `PrometheusServiceLevel` CRs**, reconciled continuously, **owned by** the environment, via an observability path that is **decoupled from provisioning**.

### D1 — Three layers: intent in the claim, objectives in policy, math in Sloth

- **Intent:** the `XEnvironment` claim already declares the services and `tier`. That is the SLO input. Teams declare *what*, never PromQL.
- **Policy:** a central `tier → objectives` catalog owned by the observability/SRE layer (e.g. `standard = 99.9% avail + p99 < 300ms`, `premium = 99.95%`). One place to change targets for everyone; overridable per service on the claim.
- **Mechanism:** Sloth owns the burn-rate PromQL. No hand-rolled rule math.

### D2 — One downstream type: Sloth `PrometheusServiceLevel` CRs

Auto-derived per-app SLOs and hand-authored platform SLOs both become Sloth CRs. Single code path for rules, dashboards, and alerts. Retire the raw-PromQL + `mimirtool` `app-slos` pipeline; unify on Sloth.

### D3 — A watcher keyed off `XEnvironment`, NOT the env Composition

A **Crossplane composition function (or a thin `XSLO` composite)** keyed off the `XEnvironment` emits the Sloth CRs; ArgoCD reconciles them. It runs *beside* the environment Composition, not inside it, so an SLO-rendering error can never block environment provisioning. Preferred over a from-scratch controller given the existing Crossplane + ArgoCD investment; a purpose-built controller is the fallback if the function model proves too limiting.

### D4 — Lifecycle coupling via `ownerReferences`

Each generated SLO CR carries an `ownerReference` to its `XEnvironment`. The SLO is **created with, healed with, and garbage-collected with** the environment. This closes the apply-lag seam and the orphan-rules problem in one move.

### D5 — Multi-signal by default

Every service, any stage, gets **availability and latency** SLOs from the same Beyla RED metrics (`http_server_request_duration_seconds` histogram). The latency threshold comes from tier policy, overridable per service.

### D6 — Tenant-aware delivery

SLO rules are evaluated in the tenant where the app metrics live (the spoke tenant), preserving the ADR-043/044 tenancy and `cluster`-label model.

## Consequences

### Positive

- SLO lifecycle **==** environment lifecycle: no seam, self-healing, auto-GC.
- One unified SLO pipeline (Sloth) for auto **and** manual SLOs.
- Latency coverage added, closing the degraded-but-up blind spot.
- Central, tier-based objectives; teams declare intent only, never PromQL.
- Environment provisioning is unaffected by SLO logic (separate reconciler).

### Negative / Known gaps

- A new moving piece (composition function / watcher) to build and own.
- Migration work: re-point the `app_slos` render to emit Sloth CRs; decommission the `mimirtool` `app-slos` sync.
- Sloth becomes a hard dependency for *all* SLOs (single point; already true for platform SLOs).
- The tier→objective policy needs an owner, a schema, and a review path.

### Risks

- A composition function reconciling toward Mimir-ruler semantics is awkward — mitigated by emitting **K8s-native Sloth CRs** and letting the existing Sloth → `PrometheusRule` → ruler path handle delivery, rather than talking to the ruler directly.
- CR volume at scale (one per service per signal) — bounded and cheap today (a handful of environments across two products); revisit sharding/derivation if it reaches hundreds of services.

## Alternatives considered

- **Keep the Terragrunt registry-derivation (status quo).** Simple and central, but carries the lifecycle seam, no GC/self-heal, and a bespoke parallel pipeline. A reasonable v1; this ADR is the v2.
- **SLO reconciliation inside the `XEnvironment` Composition.** Rejected: couples observability config onto the provisioning critical path (a bad SLO template could block a team getting an environment), and mismatches the delivery mechanism (rules land in Mimir's ruler, not as Crossplane-reconciled resources).
- **A purpose-built SLO controller watching `XEnvironment`s.** Most cloud-native and zero-lag, but more bespoke machinery than a composition function given the existing Crossplane/ArgoCD stack. Kept as the fallback.

## Related

- ADR-056 — SLOs, canary analysis, error-budget freeze (the current consumer of these rules)
- ADR-067 — registries-as-source (the `gitops/environments/**/*.yaml` registry this derives from)
- ADR-043 / ADR-044 — external `cluster` label and cross-cluster tenancy
- ADR-100 — instrumentation & OTLP convention (the RED metrics the SLIs read)
- `docs/plans/102-observability-stack.md` — W11 per-app SLOs
