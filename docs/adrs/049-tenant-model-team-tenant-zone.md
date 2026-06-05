# ADR-049: Multi-Tenancy Model — Team, Tenant, and Zone

**Date:** 2026-06-03

**Status:** Proposed — **design-stage, not yet implemented.** This ADR sets the target multi-tenancy model;
the breaking parts (the v2 claim schema, namespace naming, the `Zone`/`Customer` objects) land with the
**planned rebuild**, not as an in-place migration. It **supersedes the `team == tenant` assumption** baked
into [ADR-027](027-hybrid-tenant-isolation-model.md) (hybrid isolation) and
[ADR-031](031-multi-app-tenant-model.md) (multi-app tenant model). It **builds on**
[ADR-046](046-back-stack-for-developer-self-service.md) (BACK stack),
[ADR-048](048-federated-per-cluster-crossplane.md) (federated per-cluster Crossplane), and
[ADR-047](047-pod-identity-as-aws-identity-standard.md) (Pod Identity standard), all of which carry forward
unchanged. The isolation *primitives* of ADR-027 (namespace mode, NetworkPolicies, RBAC, quotas) are
unchanged; what changes is how tenancy is **modelled** above them.

> **This model is the schema that [ADR-053](053-identity-and-cross-system-authorization-strategy.md) consumes.**
> ADR-053's "access model as code" generates every system's RBAC from the **Team envelope** defined here, and
> Keycloak's group/role taxonomy mirrors this Team model. The two ADRs are co-dependent and both land with the
> rebuild, so **finalizing this schema is the first implementation step** — the identity/authz plumbing reads
> from it. That finalized schema (all four objects) is [tenant-api-v2.md](../architecture/tenant-api-v2.md). Note the two distinct authorization planes that both derive from this model: the **envelope**
> (`tier ∈ allowedTiers`, quota, allowed envs/locations) is enforced at *admission* by Kyverno on the `Tenant`
> CR; the **developer-access posture** (`environment × tier`, below) is *user RBAC*, propagated by ADR-053.

## Context

The current model is `team == tenant == namespace`: the `team` key on a `Tenant` claim *is* the tenant, 1:1:1
with a `team-<team>` namespace. Within a team there can be multiple apps (ADR-031), but a team has exactly
one isolation boundary, one compliance posture, and one AWS identity. This was the right call for bootstrap —
it proved the tenancy, policy, supply-chain, and Pod Identity model with minimal moving parts — but it fuses
concerns that diverge as the platform matures. The single `team` key simultaneously names and bounds the
isolation boundary, the compliance tier, the AWS identity, developer access, the supply-chain trust, ingress,
and RBAC.

We now need to design ahead for **shape and scale**, specifically:

- **Org growth / bigger teams** — a team owning several services with different blast radii.
- **Regulatory / compliance** — workloads (PCI, HIPAA) that need stronger isolation than a shared namespace:
  dedicated compute, separate accounts, controlled egress, audit, separation of duties — and **prod**, not
  just preprod.
- **Customer isolation** — enterprise customers who contractually require their workloads be completely
  isolated from other customers.
- **Data residency** — contractual obligations to run in a specific region or set of acceptable regions.
- **Multi-cloud** — the platform is multi-cloud by design (AWS-first today); the tenant-facing API must not
  leak cloud specifics, and cloud-specific mechanisms (account vending, etc.) should be used as little as
  possible.

Where `team == tenant` bites concretely: a team gets one `Pod-team` role / one Pod Identity SA (two apps
needing different AWS access can't be expressed); one isolation boundary (a sensitive workload can't be
separated from a general one without inventing a fake team); no shared or per-customer tenants; and "team"
(people/ownership) can't be modelled apart from "tenant" (a deployable, isolated unit).

## Decision

Adopt a model that **separates ownership from isolation from placement**, with three first-class dimensions
the current model lacks: **environment**, **isolation strength**, and **location**.

### Object model

Four objects (a developer/team-lead authors only the **Tenant**):

| Object | What it is | Source of truth |
| ------ | ---------- | --------------- |
| **Team** | The owner: an SSO group + an **envelope** (allowed tiers, quota cap, allowed envs/locations, max dedicated zones), cost center. Owns N Tenants; has no namespace itself. | Interim registry → Backstage `Group` (later). **Projected onto each cluster as a CR** so admission control can read the envelope. |
| **Tenant** | A logical isolation unit owned by a Team (e.g. `payments-api`). Declares intent + constraints; realized per environment. | A `Tenant` claim (Crossplane XR), authored per `(tenant, environment)`. |
| **Zone** | An account + cluster with an isolation policy — the unit of **hard** isolation and infra provisioning. Keyed by `(environment, location, hardening, tenancy)`. | **Platform-owned**, never authored by developers. Pooled zones are pre-provisioned; dedicated zones are vended. |
| **Customer** | A lightweight placement attribute (name, compliance needs, contacts) — only relevant for dedicated zones. | Interim registry → Backstage entity. |

So: **Team → N Tenants → each placed into a Zone → a namespace within it.** Ownership (Team) and isolation
(Tenant/Zone) become independent axes.

### Three orthogonal placement axes

A Tenant declares **intent + constraints**; a **placement** step resolves them to a concrete Zone. The three
axes are independent:

1. **Hardening** (`tier`: `standard` / `pci` / `hipaa` / …) — *how locked down*. The tier is a **reference to
   a platform-defined profile**, not a set of primitives; the profile bundles three platform-decided postures
   — **isolation** strength + policy set, **recovery** (RPO/RTO/retention), and **availability** (AZ spread/SLO)
   — all keyed off the one `tier` (developers pick the level, the platform decides what the level means; see
   [tenant-api-v2.md](../architecture/tenant-api-v2.md#tier-profiles--isolation--recovery--availability)).
2. **Tenancy** (`pooled` / `dedicated(customer)`) — *shared with peers, or a private home for one customer*.
3. **Location** (`residency`) — *which `(cloud, region)` it may sit in*. "Region" generalizes to
   `(cloud, region)` = a **location**, so **data residency and multi-cloud are the same mechanism**: a tenant
   states a jurisdiction (`"eu"`) or exact location, never a hardcoded region.

### Isolation spectrum (hardening → strength)

| Tier | Compute isolation | AWS account | Cluster | Network |
| ---- | ----------------- | ----------- | ------- | ------- |
| `standard` | namespace (PSA + Kyverno) | shared **env** account | shared env cluster | namespace NetworkPolicies, shared egress |
| `elevated` | + dedicated **node pool** (taints/tolerations) | shared env account | shared env cluster | + dedicated subnet / egress controls |
| `regulated` (`pci`/`hipaa`) | **dedicated cluster** | dedicated **compliance-boundary** account | dedicated regulated cluster | private, controlled/deny egress, full audit |

**The boundary is the unit of hard isolation; the tenant is the unit of soft isolation within it.** Regulated
tenants default to sharing a **compliance-boundary** zone (one dedicated account+cluster per
`(env, regime)`, e.g. `prod-pci`, namespace-isolated within) — *not* one cluster per tenant, which is
operationally untenable and not what the regulations require. A tenant escalates to its own boundary only as
an explicit exception (a customer demanding single-tenancy, incompatible same-tier requirements, or a
specific high-value blast-radius concern).

### Zones, pools, and vending

A Zone is realized as a concrete `(cloud, region, account, cluster)`:

- **Pooled zones** (standard + regulatory) are a small, stable cross-product of `tiers × locations-operated`.
  They are **provisioned statically by Terragrunt** (platform infra) — the platform team manages capacity.
- **Dedicated zones** (per customer) can grow without bound, so they need an automated **vending** path
  (an account factory). The vending **interface is cloud-neutral** ("provision a zone in `(cloud, region)`
  with hardening `X`"); the cloud-specific implementation (AWS Control Tower / an Organizations Composition /
  a per-customer generator; Azure landing zones) sits underneath and is **swappable**. The choice of vending
  mechanism is **deferred** — it is the one place a cloud-specific method is justified, and it is bounded to
  this single growing case.

This respects the **Terragrunt/Crossplane seam** (ADR-046 et al.): cluster/account provisioning (heavy, rare,
audited) stays Terragrunt; tenant provisioning (frequent, self-service) stays Crossplane; **placement** is the
thin new layer that routes a Tenant claim to the right cluster's control plane.

### The Tenant claim (cloud-neutral)

The claim is **pure intent + constraints** — it never names a cloud, region, account, cluster, or namespace
(those are derived by placement, written back to `status`). Illustrative shape (v2 API,
`platform.refplat.org/v1alpha2`); the **finalized, normative schema for all four objects** lives in
[tenant-api-v2.md](../architecture/tenant-api-v2.md):

```yaml
kind: Tenant
metadata: { name: payments-api-prod }          # logical identity = (team, name, environment)
spec:
  team: payments                               # → Team (envelope + SSO group)
  environment: prod                             # preprod | prod
  tier: pci                                     # → a platform hardening profile
  tenancy: { mode: dedicated, customer: bigbank }   # pooled (default) | dedicated(customer)
  residency: { allowedLocations: ["eu"] }       # HARD constraint; "eu" or "aws:eu-west-1"
  quota: { cpu: "8", memory: 16Gi, pods: 40 }   # validated against the Team envelope
  hostnames: ["bigbank.payments.example.com"]
  apps:                                         # delivery + per-app identity + permissions, unified
    api:
      repo: …; repoPath: k8s/prod; preview: false      # ArgoCD delivery + an ECR repo
      serviceAccount: payments-api                     # → a cloud identity is minted + bound
      permissions: { aws: { policyStatements: [ … ] } } # cloud-KEYED grants (identity stays neutral)
  developerAccess: { enabled: true }            # group override required for regulated prod
# status.placement: { cloud, region, account, cluster, zone, namespace } + ResidencyAttested  (derived)
```

Key properties: **per-app identity** (each app gets its own SA-scoped role — the fix for the single-`Pod-team`
limitation); **cloud-neutral** (the only cloud-specific field, `permissions`, is explicitly cloud-keyed while
the identity binding stays neutral); **residency is a hard, attested constraint**; and the claim **collapses
the interim `teams.hcl` split** — delivery, identity, policy subjects, and isolation all derive from one
source of truth (Team + Tenant + Zone + Customer fully replace `teams.hcl`).

### Provisioning & delivery

- **End-state (with Backstage, P5):** provisioning a tenant **into existing capacity** is a Backstage action
  with **no Terragrunt edit** — Backstage scaffolds the `Tenant` claim, validates it against the Team
  envelope, opens a PR (prod = approval gate); on merge **ArgoCD syncs the claim to the target cluster** and
  the Composition provisions everything. Expanding capacity (a new Zone — new region/regime, or a new
  dedicated-customer environment) is the **only** thing that touches platform infra (Terragrunt/vending), and
  it is a platform-team operation, not the tenant author's.

  > **Provisioning a tenant into existing capacity = self-service (GitOps). Expanding capacity = platform
  > infra.** Two changes enable this vs. today: claim delivery moves from the interim `tenant-claims`
  > Terragrunt unit to **ArgoCD/GitOps** (requiring ArgoCD's SA in the S1 backstop's platform-principal
  > exclusion to create cluster-scoped `Tenant` CRs); and the per-team **Identity Center wiring** (the
  > `Dev-<team>` permission set/group) moves into the automated path (provider-aws Identity Center resources,
  > or Backstage/SCIM). The only inherently manual step left is a human accepting their SSO invite + MFA.

- **Interim (today, pre-Backstage):** the `tenant-claims` Terragrunt unit delivers claims (applied as
  PlatformDeployer). This is acknowledged interim delivery; it does not change the model above it.

### Developer access (posture from profile)

The claim names only **who** (defaults to the Team's developer group; an override group becomes *required*
for regulated prod). The **posture** is derived from `environment × tier`, under ADR-040's rule that kubectl
is operate/debug, never authoring:

| Env × tier | Scope | Standing level | Elevation |
| ---------- | ----- | -------------- | --------- |
| preprod (any) | team-wide | operate | — |
| prod / standard | team-wide | view | operate via **break-glass** (time-boxed, audited) |
| prod / regulated | **tenant-scoped** (override group) | view | all elevation via break-glass + **approval** + audit; separation of duties (deployer ≠ approver) |

### Envelope enforcement (layered)

- **Backstage** — fail-fast UX, **advisory only** (not a security boundary).
- **Kyverno admission on the `Tenant` CR** — the **authoritative** guardrail (bypass-proof, fires however the
  claim arrived). Extends the existing S1 `restrict-tenant-control-plane` backstop with "…and only within
  your Team's envelope." Handles the **stateless** checks (`tier ∈ allowedTiers`,
  `environment ∈ allowedEnvironments`, `residency ⊆ allowedLocations`, per-tenant quota shape). Requires the
  Team to be readable on the cluster — hence the **Team-as-projected-CR** design above.
- **Aggregate checks** (team total quota ≤ cap, ≤ max dedicated zones) are cross-object/stateful — start with
  **report/alert**, add a small rollup controller to hard-enforce only if a team actually pushes the cap.

## Alternatives considered

- **Keep `team == tenant`.** Simplest, but cannot express multiple tenants per team, per-app AWS identity,
  customer isolation, or per-tenant compliance — the requirements above. Rejected as the target.
- **Account/cluster *per tenant* as the default.** Strongest isolation, but cost- and ops-prohibitive (N
  regulated clusters) and not what compliance requires; boundary-level isolation is the right default, with
  per-tenant as an explicit exception. Rejected as default.
- **Dynamic vending for *all* zones.** Maximal self-service, but pushes Crossplane across the
  infra-provisioning seam for the common case and adds large operational surface. Static pools for
  shared/regulatory zones + vending only for dedicated zones is the defensible hybrid. Rejected (kept for
  dedicated only, deferred).
- **Backstage as the enforcement boundary.** Good UX but bypassable; not a security control. Rejected as the
  authoritative layer (kept as advisory).
- **A deeper hierarchy now** (Org → Folder → Project → Tenant). Over-models for the current forcing
  functions; two ownership levels (Team → Tenant) + the isolation spectrum cover org growth and regulatory
  cases. Deferred until a real need.

## Consequences

### Positive

- Scales with org growth, regulated **prod** workloads, **multi-cloud**, **data residency**, and
  **customer isolation** — the stated drivers — without expanding Crossplane's footprint or operational
  surface beyond what the requirement forces.
- Decouples **ownership** (Team) from **isolation** (Tenant/Zone); **per-app AWS identity** falls out.
- The Tenant API is **cloud-, region-, and account-neutral** — developers never name a cloud — which is what
  makes the multi-cloud goal real rather than aspirational.
- Clean **self-service** end-state (Backstage → GitOps), with a crisp seam: tenants self-served, capacity
  platform-managed.
- Collapses the interim `teams.hcl` split into one source of truth.

### Negative / cost

- More concepts (Team, Tenant, Zone, Customer) and a new **placement** layer to build and operate.
- The claim API is **v2 / breaking** (namespace naming `<team>-<tenant>`, schema) — must land with the
  rebuild, not in place.
- New surface: **Zone** provisioning (pools) and the **vending** path (deferred); aggregate envelope
  enforcement eventually needs a controller; the SSO-automation and ArgoCD-delivery changes are prerequisites
  for end-state self-service.
- Isolation between same-tier tenants in a shared boundary remains namespace-level (soft) — acceptable by
  design, with escalation-to-own-boundary as the release valve, but it must be a conscious, documented call
  per regulatory target.

### Migration / rebuild

- The breaking changes land with the **planned rebuild** (the stack is destroyed/recreated from scratch);
  no in-place migration of the current `team == tenant` tenants.
- The **federated per-cluster** model (ADR-048) maps directly: a Zone *is* an environment+location cluster
  running its own Crossplane + Composition; placement routes a claim to the right one.
- Until the rebuild, the **interim** model stands: `team == tenant`, `teams.hcl` for delivery + supply-chain,
  the `tenant-claims` Terragrunt unit for delivery, and the manual Identity Center steps
  (see [tenant-onboarding](../runbooks/tenant-onboarding.md)).
- Open, explicitly deferred — **reserved in the v2 schema** ([tenant-api-v2.md](../architecture/tenant-api-v2.md#reserved-dimensions-modeled-now-realized-post-rebuild)),
  realized post-rebuild so the API needn't break to gain them: the **dedicated-zone vending mechanism** (behind
  a cloud-neutral interface), the **aggregate-quota controller** (report-first), the **data-services paved
  road** (+ its data-residency attestation), per-tier **recovery/availability** realization (a backup/DR
  system — [ADR-054](054-platform-resilience-and-business-continuity.md)), **encryption key custody**
  (BYOK/HYOK), and tenant/customer **lifecycle-exit** (certified destruction, retention holds). **Consumption
  guarantees** (QoS/priority — `quota` is a cap, not a reservation) are a named, conscious omission.
- Related platform-capability ADRs that surround this model:
  [ADR-054](054-platform-resilience-and-business-continuity.md) (resilience/DR — realizes the tier recovery +
  availability postures), [ADR-055](055-compliance-assurance-and-continuous-control-evidence.md) (compliance
  *assurance* over the tier controls), [ADR-056](056-progressive-delivery-and-safe-rollback.md) (safe prod
  rollout, gated by the tier SLO), [ADR-057](057-service-identity-and-east-west-zero-trust.md) (east-west
  mTLS — refines the tier's network posture), and
  [ADR-058](058-per-cloud-tenant-composition-strategy.md) (how the neutral claim is realized per cloud —
  shared XRD, per-cloud Compositions selected by placement).
