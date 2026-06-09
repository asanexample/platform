# ADR-063: Team as a First-Class Git-Native Object

**Date:** 2026-06-09
**Status:** Proposed — design-stage. Sharpens the **Team** source-of-truth left open in
[ADR-049](049-tenant-model-team-tenant-zone.md) / [tenant-api-v2.md](../architecture/tenant-api-v2.md); lands
with the rebuild. Enables [ADR-062](062-self-service-tenant-provisioning.md) (self-service).

## Context

[ADR-049](049-tenant-model-team-tenant-zone.md) makes **Team** a first-class object — the owner that carries
the **envelope** (allowed tiers/envs/locations, quota cap, max dedicated zones) and the SSO group, owns N
Tenants, and is **projected onto each cluster as a CR so Kyverno can validate Tenant claims against it at
admission**. But it leaves the Team's *source of truth* deliberately vague: *"Interim registry → Backstage
`Group` (later)."*

Today that "interim registry" is **HCL** — `infra/live/aws/_teams.hcl` (envelope + ssoGroup, read by the
`crossplane` and `keycloak-config` units) plus a second app-delivery `teams.hcl` (read by `policy` and
`argocd-apps`) and a hand-maintained `teams` local in `github-oidc`. So "a Team" is restated across four HCL
locations in three formats — migration-era duplication that predates the Tenant claim. This blocks two things:
it keeps governance config in a different shape/place from everything else (which is git-native declarative
YAML reconciled by ArgoCD/Crossplane), and it means onboarding a Team is an HCL edit, not a portal action — at
odds with the self-service direction ([ADR-062](062-self-service-tenant-provisioning.md)) and the
"claim-as-single-source" goal.

## Decision

### 1. The Team becomes a first-class, git-native declarative object

A `Team` is authored as a **declarative object in git** (`gitops/teams/<team>.yaml`), parallel to the Tenant
claim — same *kind* of thing (a Crossplane XR / CR reconciled in-cluster, read from git by the units that need
it), differentiated only by **who may author it**: a Team via the admin-only *New Team* flow
([ADR-062](062-self-service-tenant-provisioning.md) §1), a Tenant via the team-scoped *New Tenant* flow.

The **envelope lives on the Team object**; it is projected to the Team CR that Kyverno already looks up by name
(`/apis/platform.refplat.org/.../teams/<team>`) to validate each Tenant claim. No new admission mechanism — this
is the source-of-truth for the CR ADR-049 already specifies, moved from HCL into git.

### 2. `_teams.hcl` and the app-delivery `teams.hcl` are retired

Consumers derive per-team config from the **Team object** (governance: envelope, ssoGroup, dev-access posture)
and the **Tenant claims** (delivery: `apps.repo`, hostnames, quota requested) — never from the HCL registries.
This is the **claim-as-single-source** consolidation:

| Unit | Today reads | After |
|------|-------------|-------|
| `crossplane` (Team CR projection) | `_teams.hcl` envelope | the `Team` objects |
| `keycloak-config` (group + dev-access role) | `_teams.hcl` | the `Team` objects |
| `policy` (verify subjects, signer, hostnames) | app-delivery `teams.hcl` | the `Tenant` claims (`apps.repo`, `spec.domains`) |
| `github-oidc` (ECR-push role per team) | hand-maintained `teams` local | the `Tenant` claims (`apps.repo`) |
| `argocd-apps` (apps + previews) | app-delivery `teams.hcl` | the `Tenant` claims (already reads claims for domains) |

The **governance / delivery split is the invariant**: governance (envelope, identity) is platform-authored on
the `Team`; delivery (apps, repos, hostnames, requested quota) is team-authored on the `Tenant`. Kyverno
validates the latter against the former. Nothing a *team* authors can widen its own envelope — the escalation
boundary of [ADR-062](062-self-service-tenant-provisioning.md) §4.

### 3. No default envelope — Team creation stays explicit

We considered (and rejected) a default-envelope shortcut (any Tenant claim auto-gets a standard/preprod
envelope). It weakens authorization to default-allow and removes the explicit per-team grant. Instead, **every
Team is explicitly created** (the *New Team* admin flow) — a deliberate governance act that sets the envelope.
This keeps every tenant provably authorized and is why `New Team` is human-reviewed, never automerged.

## Consequences

- One consistent model: Teams and Tenants are both git-native declarative objects; governance config leaves HCL.
- Onboarding a Team is a reviewed git change (portal-driven for admins), not an HCL edit across four files.
- This is a **breaking, rebuild-time** change (it restructures how four units read team config and removes
  `_teams.hcl`); it is built into the fresh IaC and bootstrapped clean, not migrated in place
  ([[project_planned_rebuild]]).
- Each unit refactor must be verified a behaviour-preserving **plan no-op** for the existing teams at rebuild
  parity.

## Relationships

- **Sharpens** [ADR-049](049-tenant-model-team-tenant-zone.md) / [tenant-api-v2.md](../architecture/tenant-api-v2.md)
  (the Team object's source of truth). The Team *schema* remains tenant-api-v2's; this ADR fixes *where it lives*.
- **Enables** [ADR-062](062-self-service-tenant-provisioning.md) (the *New Team* flow authors this object).
- **Consumed by** [ADR-053](053-identity-and-cross-system-authorization-strategy.md) (the envelope is the
  access-as-code source) and the Kyverno envelope guardrail ([ADR-014](014-kyverno-as-policy-engine.md)).
- Retires `infra/live/aws/_teams.hcl` and `infra/live/aws/preprod/us-east-1/platform/teams.hcl`; touches the
  `crossplane`, `keycloak-config`, `policy`, `github-oidc`, and `argocd-apps` units.
