# Tenant API schema tests

Offline validation of the **Tenant API** XRD (`../charts/tenant/templates/xrd.yaml`) — the first
implementation step of the v2 tenant model (delivery-plan **A1**;
[ADR-049](../../../../docs/adrs/049-tenant-model-team-tenant-zone.md),
[schema](../../../../docs/architecture/tenant-api-v2.md)).

`run.sh` uses `crossplane beta validate` to check example claims against the XRD's OpenAPI v3 schema **and**
its `x-kubernetes-validations` CEL rules — **no cluster, no Composition**. It is the `v2` analogue of the
Kyverno `.kyverno-tests` harness, and CI runs it via the **Tenant API Schema** job.

```text
claims/    valid v1alpha2 claims that MUST pass — canonical (every field + reserved dimensions)
           + alpha/bravo translated from the live v1alpha1 claims (gitops/tenant-claims/preprod/)
invalid/   claims that MUST be rejected — bad tier enum, dedicated-without-customer (CEL),
           missing required field
```

Run locally:

```bash
infra/modules/crossplane/.tenant-api-tests/run.sh    # needs the crossplane CLI on PATH
```

Scope: this validates the **schema only**. Cross-object envelope checks (tier ∈ `Team.allowedTiers`,
quota ≤ cap, residency ⊆ allowed locations) are Kyverno's job against the projected `Team` CR (plan **A2**);
rendering the tenant footprint from a claim is the v2 Composition (plan **A3**). `v1alpha2` is served-only —
`v1alpha1` stays the referenceable/storage version until the rebuild cutover (plan **A6**).
