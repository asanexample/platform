# ADR-090: Governance Identity Model — one source for role-holding, and the layer glossary

**Date:** 2026-06-29

**Status:** Proposed (design — 2026-06-29)

## Context

The workforce-governance model has grown several first-class git-native objects — `Team`, `WorkforceRole`,
`Person`, `Activation` (ADR-063/067/084/088) — alongside the tenant/app model (`Product`, `Environment`,
`Release`, `AccessGrant`). A coherence review surfaced two rough edges:

1. **A real redundancy.** Governance roles — **`team-admin`** and **`release-approver`** — are modeled in two
   places: as a **`WorkforceRole` held via a `Person` grant**, *and* as a hand-authored **GitHub-login list on
   `Team.roles.{teamAdmin, releaseApprover}`** (and `Product.spec.roles.releaseApprover`). The *same fact* —
   "who administers / can approve for team X" — is authored twice, in two formats, that can drift. This violates
   the north-star principle (*decide once, project everywhere*). Notably, [ADR-068](068-product-scoped-and-cross-team-access-model.md)
   already *intended* `release-approver` to be "a **generator-managed role** (git/Keycloak = source of truth),
   **projected into CODEOWNERS / a required-reviewer set**" — but #501 implemented it as the hand-authored
   `Team.roles` field, so the implementation drifted from the intent.

2. **Naming overload.** "role" names two things (`WorkforceRole` vs `Team.roles`); "grant" names two things
   (`Person.grants` vs the `AccessGrant` CRD). The things are genuinely distinct, but the shared words make the
   model harder to hold in one's head.

The redundancy is currently **latent**: `Team.roles` is populated and drives the live PR gate, but **no one holds
`team-admin`/`release-approver` via a `Person` grant yet**. So we can set the single home *before* there is
double-authored data to reconcile — much cheaper now than later.

## Decision

**D1 — Name the four layers.** The platform's git-native objects fall into four distinct layers; conflating them
is the root of the confusion:

| Layer | Objects | Nature |
|-------|---------|--------|
| **Governance / identity registry** | `Team`, `WorkforceRole`, `Person` | slow, platform-authored — "who, and what's allowed" |
| **Runtime / operational** | `Activation` | controller-owned — "what's happening now" |
| **Tenant / app model** | `Product`, `Environment` (`XEnvironment`), `Release` | the deployment units |
| **Machine / service access** | `AccessGrant`, `XAgent` | a separate plane — workload-to-workload, not human |

**D2 — The `Person` is the single source of truth for who-holds-which-role-at-which-reach.** ALL role-holding —
**including governance roles (`team-admin`, `release-approver`)** — is authored once, as a `Person` grant
(`role × reach`). Governance roles are `WorkforceRole`s like any other; they merely project to more surfaces (a
governance role projects to *both* IC/Keycloak access *and* the PR-approval gate).

**D3 — `Team`/`Product` approver designations are DERIVED, not authored.** `Team.roles.{teamAdmin,
releaseApprover}` and `Product.spec.roles.releaseApprover` become a **generated projection** of `Person` grants
— the People holding that role for the team/product → their `spec.handles.github` → the CODEOWNERS /
required-reviewer set the gated-prod gate enforces. This **realizes ADR-068's stated "generator-managed role,
projected" intent** and **revises [ADR-063](063-team-as-first-class-git-object.md)**'s hand-authored `Team.roles`.
Retiring the authored field removes the redundancy *and* the "role" naming overload — with `Team.roles` gone,
**"role" means `WorkforceRole`, full stop.**

**D4 — Keep `AccessGrant`; resolve "grant" with the glossary, not a rename.** `Person.grants` (human → role) and
the `AccessGrant` CRD (service → cross-team product) sit on **different planes** (workforce vs machine, per
ADR-074 / the identity strategy) — genuinely distinct, not redundant. `AccessGrant` is a built, live CRD
(ADR-068); renaming it is not worth the churn. The distinction is carried by the glossary (D5). (If the clash
keeps biting, the eventual clean rename is `AccessGrant` → a service-flavored name, since it is the outlier — it
is about products, not workforce — but that is deferred.)

**D5 — Glossary (the precise meaning of each term).**

| Term | Means | Not to be confused with |
|------|-------|--------------------------|
| **WorkforceRole** | a workforce *access* role a person can hold (developer, break-glass, team-admin, …) | `Team.roles` (retired) |
| **Person grant** | one `(WorkforceRole × reach)` a person holds; the **single source** for role-holding | `AccessGrant` |
| **reach** | a grant's scope — exactly one of a `Team` or platform-wide | — |
| **Activation** | a live, time-boxed *borrow* of a person's on-demand role grant | a standing grant |
| **AccessGrant** | cross-team **service/product** access (team A's workload → team B's product) | a `Person` grant |
| **Team envelope** | the limits a team may deploy within (`Team.spec.envelope`) | a person's access |

## Consequences

### Positive

- **One source** for role-holding — no silent drift between `Team.roles` and Person grants.
- **Aligns the implementation with ADR-068's intent** (release-approver as a projected, generator-managed role).
- **Clearer model**: "role" means exactly one thing; the four layers are named; the glossary settles "grant."
- Fixing it now (while latent) avoids a later reconcile of double-authored data.

### Negative / Risks

- **Touches the live gated-prod approval gate (#501 / ADR-068).** The migration must be sequenced (below); a
  careless change could block or mis-authorize a prod promotion.
- The derived approver set is **eventually consistent** (a generation/sync step) rather than a flat hand-edited
  list — a small added moving part, mitigated by the generator + a validation that the projection is fresh.

## Migration (sequence — do not big-bang the live gate)

1. **Author the Person grants** for whoever is in `Team.roles`/`Product.roles` today (e.g. give the platform
   team-lead a `release-approver` grant on the platform team).
2. **Switch the gated-prod gate to DERIVE** approvers: People holding `release-approver` for the team/product →
   `handles.github` → the required-reviewer set (the gate already reads the gitops registries).
3. **Drop the hand-authored** `Team.roles` / `Product.spec.roles.releaseApprover` fields.

## Alternatives considered

- **Keep both homes + a CI drift-check.** Rejected — still two sources of truth; a drift-check papers over the
  incoherence rather than removing it.
- **Make `Team.roles` the source; remove `team-admin`/`release-approver` from the `WorkforceRole` catalog.**
  Rejected — those *are* access roles (they project to IC/Keycloak), so they belong in the catalog; and "some
  roles live on the Team, others on the Person" splits the model in a worse way.
- **Rename `AccessGrant` now.** Deferred — it is a live CRD (ADR-068); the glossary resolves the clarity cost
  without the rename churn.

## Related

- [ADR-063](063-team-as-first-class-git-object.md) (revises its hand-authored `Team.roles`),
  [ADR-068](068-product-scoped-and-cross-team-access-model.md) (realizes its release-approver projection intent),
  [ADR-067](067-idp-domain-model.md) (the domain model), [ADR-074](074-agentic-workloads-platform.md) (workforce vs
  machine plane), [ADR-088](088-temporary-power-activation.md) (Activation = the runtime borrow),
  [ADR-089](089-governance-registry-topology.md) (where these registries are projected).
- `docs/architecture/identity-and-access-strategy.md` (the north-star this makes coherent).
