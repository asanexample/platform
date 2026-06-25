# ADR-081: Platform-Team Products on the One Delivery Road — Unified Provisioning + Per-Environment Placement

**Status:** Proposed (2026-06-24)

## Context

Internally-developed, platform-owned services and agents had no standard delivery path: backstage and the ARC runner are
bespoke Terragrunt-Helm one-offs, and [ADR-080](080-triage-copilot.md)'s triage copilot was on track to be a third. The
first instinct (an earlier draft of this ADR) was a *parallel* "platform-services" GitOps road alongside the tenant one.

That was the wrong call. **A parallel road is duplication** — a second ApplicationSet, a second registry, a second
promote/validation story — and it re-introduces exactly the platform-vs-tenant split the platform is trying to erase.
Platform-team products are *more* trusted than dev-team products, **but not by much**, and they deserve the same
structure, gating, validation, and promotion as everyone else. There should be **one delivery road**.

## Decision

**The platform team is a first-class Team, and its products flow through the entire tenant delivery machinery** — the
`Product`/`XEnvironment`/`Release` registries, the Crossplane Environment **Composition**, the per-Product
`ApplicationSet`, `promote.yml`, the gitops Gate, and the Kyverno envelope — with exactly **two generalizations**:

1. **Placement** is a per-**Environment** property (which cluster a deployment lands on), realizing the long-degenerate
   `Deployment → Placement` of [ADR-067](067-idp-domain-model.md).
2. A **platform-trust envelope** lets the platform Team declare what tenants can't (cluster-scoped read, the Bedrock
   action, broader namespaces) — but it is still an envelope, still admission-gated.

There is **one provisioning path for everyone.** A platform product is provisioned by the same Composition that
provisions tenant products, wherever it lands.

## Design

### D1 — `platform` is a Team

`gitops/teams/platform.yaml` is a normal `Team` with a **platform-trust envelope** (D6). Its products live at
`gitops/products/platform/<product>.yaml`; the triage copilot is the **reference product**.

### D2 — Placement is a per-Environment property (the multi-cluster seam)

The `Environment` declares its target cluster: `spec.cluster: platform | preprod | prod` (default **`preprod`** — today's
behavior, so nothing existing changes). The per-Product ApplicationSet resolves `destination.name` from it against
ArgoCD's registered clusters; the Composition provisions on that cluster. **Placement is not a platform concept** — any
team's environment can set it — it just *happens* that the triage copilot's first Environment targets `platform`. A later
platform agent might target `preprod` or `prod`; a tenant could one day multi-cluster too. No platform special-case.

### D3 — One Composition provisions everything

A platform product's `XEnvironment` is provisioned by the **same Composition** as tenants — namespace, ResourceQuota,
per-Service identity, ECR — generalized to (a) be **placement-aware** (provision on `spec.cluster`) and (b) honor the
**platform-trust envelope**. No platform-specific Terragrunt provisioning units.

### D4 — Identity via the existing per-Service policyStatements

The agent's `bedrock:InvokeModel` is declared as a normal `services.<svc>.permissions.aws.policyStatements` entry and
minted as a per-Service **EKS Pod Identity** role by the Composition — the same mechanism tenant services use for AWS
access. Bedrock is not in the deny-set ([ADR-062](062-self-service-tenant-provisioning.md) §4), so it passes the envelope
validator unchanged. **No bespoke identity unit.**

### D5 — Supply chain via the shared backbone

The agent is a thin caller of `asanexample/trusted-ci/build-sign.yml` + `slsa-provenance.yml` + `promote.yml` like any
app ([ADR-050](050-shared-build-sign-reusable-workflow.md)/[ADR-071](071-digest-promotion-via-control-plane.md)). Its
image is the tenant-shaped `team-platform/<product>-<svc>`, built by the registry-derived per-Product OIDC role,
cosign-signed, SBOM'd, and digest-promoted into `gitops/releases/platform/<product>/<stage>.yaml`. **No dedicated ECR or
OIDC role; no bespoke `build.yml`.**

### D6 — The platform-trust envelope (the "more or less")

The platform Team's envelope is broader than a tenant's — it may allow **cluster-scoped read RBAC** (an observability
agent reads across namespaces; tenants are namespace-scoped), the **Bedrock action**, and platform-appropriate stages —
but it is the **same envelope mechanism**, declared in `gitops/teams/platform.yaml`, validated at admission. Trust is a
*parameter* of the one model, not a second model.

### D7 — This supersedes the parallel-road approach

The earlier `gitops/platform-services` registry + separate ApplicationSet (and the platform-specific Pod Identity / ECR /
OIDC units merged as #685/#686/#688) are **withdrawn** in favor of the single road: the agent becomes a `platform`-team
Product. backstage / gha-runner MAY migrate onto it later (out of scope).

## Scope

- **In:** `platform` as a Team; per-Environment Placement (the ApplicationSet + Composition generalization); the
  platform-trust envelope; the triage copilot re-expressed as a `platform`-team Product (reference instance).
- **Out (for now):** migrating backstage / gha-runner; registering the prod cluster as an ArgoCD destination (done when a
  prod-targeted Environment first needs it); a declarative `Agent` CRD (a future layer above this, ADR-074).

## Consequences

- **One road, no platform exceptions** — same registries, gating, validation, promotion, and provisioning for platform
  and tenant products alike. Onboarding any platform service is a Team-scoped Product, identical to a tenant Product.
- **The cost is real: the Composition must generalize** — placement-awareness (provision on a named cluster, not just
  preprod) and the platform-trust envelope are non-trivial changes to tenant-critical infra and must be done carefully.
- **Today's merged work folds away** (#685/#686/#688) — cheaply, since nothing was applied. The agent's identity, image,
  delivery, and provisioning all collapse onto the standard path.
- Placement is a genuinely useful capability beyond platform — it is the start of real multi-cluster delivery.

## Alternatives considered

- **A parallel platform-services road** (this ADR's earlier draft). Rejected — duplication, and it re-creates the
  platform-vs-tenant split.
- **Unify governance/delivery but keep platform-specific provisioning units.** Rejected — the moment a platform product
  targets preprod/prod it needs provisioning *there*, which is exactly what the Composition already does; platform units
  quietly re-introduce the split.

## Related

- [ADR-067](067-idp-domain-model.md) — the Team→Product→Environment model + the `Placement` concept this realizes.
- [ADR-069](069-delivery-source-of-truth-product-environment.md) / [ADR-071](071-digest-promotion-via-control-plane.md) —
  the delivery source-of-truth + digest promotion the platform Team reuses unchanged.
- [ADR-062](062-self-service-tenant-provisioning.md) — the policyStatements deny-set the agent's Bedrock identity passes (D4).
- [ADR-074](074-agentic-workloads-platform.md) — agents as a workload class; a future declarative `Agent` CRD above this road.
- [ADR-080](080-triage-copilot.md) — the triage copilot, this road's reference product.
