# Tenant API schema tests

Offline validation of the **Tenant API** schemas — the `XTenant` XRD (`../charts/tenant/templates/xrd.yaml`,
delivery-plan **A1**) and the projected `Team` CRD (`../charts/tenant/templates/team-crd.yaml`, **A2**) — of
the v2 tenant model ([ADR-049](../../../../docs/adrs/049-tenant-model-team-tenant-zone.md),
[schema](../../../../docs/architecture/tenant-api-v2.md)).

`run.sh` uses `crossplane beta validate` to check example claims against the XRD's OpenAPI v3 schema **and**
its `x-kubernetes-validations` CEL rules — **no cluster, no Composition**. It is the `v2` analogue of the
Kyverno `.kyverno-tests` harness, and CI runs it via the **Tenant API Schema** job.

```text
claims/        valid XTenant claims that MUST pass — canonical (every field + reserved dimensions)
               + alpha/bravo translated from the live v1alpha1 claims (gitops/tenant-claims/preprod/)
invalid/       XTenant claims that MUST be rejected — bad tier enum, dedicated-without-customer (CEL),
               missing required field
teams/         valid projected Team records that MUST pass — payments (canonical) + alpha/bravo
teams-invalid/ Team records that MUST be rejected — bad tier enum, missing envelope
registry-values.yaml  canonical Team registry (full records) — input to the crossplane-teams chart;
                      run.sh renders it, validates the projection against the Team CRD, and asserts the
                      canonical-only fields (displayName/developerGroup/costCenter/contacts) are dropped
```

The **registry → projection** step (delivery-plan A2) renders the `../charts/teams` chart from the canonical
registry into projected `Team` CRs (the envelope subset) and validates them — the mechanism that puts Team CRs
on a cluster. The module installs the chart via `helm_release "crossplane_teams"` with `var.teams` (default
empty); the live registry is supplied at the unit. Needs `helm` (the CI job installs it).

Run locally:

```bash
infra/modules/crossplane/.tenant-api-tests/run.sh    # needs the crossplane CLI on PATH
```

Scope: this validates the **schemas only** (structure + enums + CEL). The Team CRD lands here; the **Kyverno
envelope policy that reads it** — the cross-object checks (tier ∈ `Team.allowedTiers`, quota ≤ cap, residency ⊆
allowed locations) — is the next step (plan **A2b**, in the `policy` module). Rendering the tenant footprint
from a claim is the v2 Composition (plan **A3**). `v1alpha2` is served-only — `v1alpha1` stays the
referenceable/storage version until the rebuild cutover (plan **A6**).
