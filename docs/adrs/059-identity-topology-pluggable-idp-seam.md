# ADR-059: Identity Topology — Keycloak as the Pluggable Identity Seam

**Date:** 2026-06-05

**Status:** Accepted — **strategy/direction.** Refines [ADR-053](053-identity-and-cross-system-authorization-strategy.md)
(Keycloak as the app-facing IdP, access-model-as-code) and the
[ADR-052](052-centralized-dex-sso-broker.md) vendor-neutral issuer seam: it reframes "Identity Center is the
user store, Keycloak brokers *up* to it" as one **instance** of a general topology in which Keycloak is a stable
seam and the **upstream IdP is pluggable.** Builds on the realized B1/B2 work (the `keycloak` +
`keycloak-config` modules, the access-model registry). Lands with the planned rebuild
([ADR-049](049-tenant-model-team-tenant-zone.md)); informs the deferred membership/SCIM work and the
ArgoCD/Backstage cutovers (B3/B4, #197).

> **Note (2026-06-27, accuracy review):** the body refers to the access-model source of truth as
> **`_teams.hcl`**. That HCL registry has since been **retired** — the access model is now the git-native
> **`Team`** object (`gitops/teams/`) plus the `Product` registry ([ADR-063](063-team-as-first-class-git-object.md) /
> [ADR-067](067-idp-domain-model.md)). Read every `_teams.hcl` reference below as that registry.

## Amendment — 2026-06-08: Scenario B is the realized default

This ADR already framed the upstream IdP as pluggable and called the AWS-IdC topology (scenario C) "a bootstrap,
not the destination." We are now making that concrete: **the realized default is scenario B — Keycloak is the IdP
of record** (owns users + memberships in the `platform` realm), with scenarios A (Okta/Entra federation) and C
(AWS IdC) as **opt-in `upstream` configurations**, not the baseline.

- **`keycloak-config` defaults to `upstream = null`** (standalone). Users are seeded as code (the `users` input)
  and placed directly into team / platform groups, so the **membership binding is local** and the
  group→role→claim flow is live with no upstream — closing the membership gap by construction rather than waiting
  on a group-emitting upstream.
- **The seam is unchanged** — federation is still a one-block swap: set `upstream` to SAML (IdC) or OIDC
  (Okta/Entra/Google) and *nothing downstream moves*. With a group-emitting upstream, membership flips from the
  local `users` seed to the IdP-group→Keycloak-group mapper (decision 3's default mechanism); with IdC it stays
  on the `_teams.hcl`/UI fallback.
- **Membership source of truth by mode:** standalone → seeded `users` (+ admin UI); federated-with-groups →
  upstream group claim; federated-IdC → `_teams.hcl` / UI. The three reference scenarios below are unchanged; only
  *which one is the default* moves (C → B).

AWS access stays on Identity Center permission sets in every mode (directory-based, orthogonal to the app IdP).

## Context

Building the Team→group/role taxonomy (B2) surfaced a **membership gap**: OIDC apps (ArgoCD, Backstage,
Grafana) authorize from a `groups` claim at login, so Keycloak must know each user's team memberships — but with
**AWS Identity Center** as the upstream IdP, IdC **can't emit group claims over SAML** and is a **poor SCIM
source**, so membership can't flow in. The gap is specific to **AWS Identity Center**, not to Keycloak.

That forced the underlying question this ADR answers: what is the source of truth for **identity**,
**membership**, and **access** — and how does the platform stay portable across the identity environments it must
eventually support? Three are in scope:

- **Enterprises already running Okta or Microsoft Entra ID** — the platform must integrate with (or sit
  downstream of) these, since that is what real customers run.
- **Budget-constrained orgs with no corporate IdP** — Keycloak (optionally federating to Google Workspace) is
  the whole identity stack.
- **The current AWS-IdC-on-top bootstrap** — what B1/B2 built.

Three sources of truth were being conflated. This ADR separates them.

## Decision

**Keycloak is the platform's stable identity seam. Everything *downstream* of it — apps via OIDC claims, AWS
access, the access-as-code generators — is invariant; the *upstream* IdP and the *membership-binding source* are
pluggable adapters.** Concretely, the three sources of truth are:

1. **Identity SoR = the upstream IdP — pluggable.** Okta / Entra ID / Google Workspace (enterprise), or
   Keycloak-local users (no corporate IdP), or AWS Identity Center (the current bootstrap). Keycloak brokers
   authentication from whichever; **nothing downstream changes when it swaps.** The vendor-neutral issuer seam
   (`sso.aws.refplat.org`, ADR-052) is what makes apps indifferent to the swap.
2. **Access-model SoR = `_teams.hcl` (access-as-code) — constant in every scenario.** Teams, envelopes, roles,
   and the group→role vocabulary, generated outward to Keycloak groups/roles, app RBAC, and AWS IdC assignments
   (ADR-053 decision 3; the B2 taxonomy + A2c envelope projection).
3. **Membership binding (person → team) = a pluggable adapter.** **Default:** the upstream IdP's **group claim →
   a Keycloak group mapper** — this works for Okta / Entra / Google (the realistic enterprise case) and is the
   *real* membership mechanism, which is why those upstreams "just work." **Fallbacks:** the `_teams.hcl`
   registry (when the upstream emits no groups — e.g. AWS IdC) or the Keycloak admin UI (small / no-corporate-IdP
   orgs).

### The invariant core (identical in every scenario)

```text
        [ upstream identity — VARIES ]
                    │  (OIDC / SAML federation)
                    ▼
   ┌──────────────────── Keycloak · platform realm ─────────────────────┐
   │ brokers auth from upstream · owns the platform group/role taxonomy  │
   │ · emits clean per-client OIDC group/role claims                     │
   └─────────────┬──────────────────────────────────┬───────────────────┘
                 │ OIDC claims (JIT)                 │ SAML/OIDC + SCIM
                 ▼                                   ▼
     Argo · Backstage · Grafana · Vault      AWS · Slack · GitHub · …
     (claim-based — NO provisioning)         (directory-based — SCIM/assignments)

   access-as-code:  _teams.hcl ──► generators ──► Keycloak groups/roles ·
                                   app RBAC · AWS IdC assignments · SCIM mappings
```

### Three reference scenarios

**A — Enterprise (Okta / Entra ID) — the design target.** Okta/Entra is the identity SoR + lifecycle; their
workforce **group claim** flows through Keycloak into a group mapper (membership "just works", no inbound SCIM).
AWS stays on Identity Center permission sets (generated). The registry maps the org's IdP groups → platform
teams/roles.

```text
  Workday/HR ─JML─► Okta / Entra ──(OIDC federation, group claim)──► Keycloak (broker)
                    • identity SoR + MFA                              • claim-shaper + taxonomy
        ┌────────────────────────────────────┼─────────────────────────────┐
        ▼ OIDC claims                         ▼ SAML→AWS IdC                 ▼ SCIM
   Argo / Backstage / Grafana            AWS (permission sets)         Slack / GitHub
```

**B — Bootstrapped startup (no corporate IdP) — Keycloak-as-hub.** Keycloak owns users (local, or federated to
Google Workspace) and memberships (UI or git). AWS is reached via Keycloak→IdC outbound SCIM or direct
per-account IAM federation — **the one place outbound SCIM is actually needed.**

```text
  (Google Workspace ─social login─►)  Keycloak (IdP + SoR; users + memberships)
        ┌──────────────────┼───────────────────────────┐
        ▼ OIDC             ▼ SCIM / SAML                ▼ SCIM
   Argo / Backstage    AWS (IdC or direct IAM)      Slack / GitHub
```

**C — Current build (AWS Identity Center upstream) — a bootstrap, not the destination.** IdC provides login but
**cannot emit group claims**, so membership must come from the `_teams.hcl` registry (git). This is the
membership gap — and it is an **IdC limitation, dissolved by any group-emitting upstream (A or B).**

```text
  AWS Identity Center ──SAML──► Keycloak (broker; groups EMPTY without a source)
        ▼ OIDC claims                       AWS access stays native IdC
   Argo / Backstage / Grafana
   MEMBERSHIP → from _teams.hcl (IdC can't emit groups, weak SCIM source)
```

### What stays constant

AWS access is **Identity Center permission sets** (generated from the registry) wherever IdC is present.
**Internal vs external apps are NOT an identity split** — identity is unified (one hub, one offboard). The axis
that matters is **claim-based / just-in-time** (Argo, Backstage, Grafana — no provisioning) vs **directory-based
/ SCIM** (AWS, Slack, GitHub — own their own user store).

## Alternatives considered

- **AWS Identity Center as the permanent top-of-tree** (scenario C made the destination). *Rejected:* IdC is an
  AWS-access tool, not a workforce IdP — no group claims, weak SCIM source (the membership gap). Fine as a
  bootstrap.
- **Keycloak as the hard-coded SoR everywhere** (the "Keycloak = Okta" model, forced). Viable and kept as
  **scenario B**, but mandating it everywhere fights enterprises that already run Okta/Entra and leans on
  Keycloak's weak outbound SCIM. Kept as one pluggable mode, not the only one.
- **A second identity stack for external SaaS** (split internal vs external identity). *Rejected:* identity must
  be unified; the real distinction is claim-based (JIT) vs directory-based (SCIM), which is a *provisioning*
  concern, not an identity one.

## Consequences

- The platform is **portable across Okta / Entra / Google / IdC / standalone** with no downstream change — the
  apps, AWS wiring, and access-as-code generators don't move when the upstream swaps.
- The current AWS-IdC build becomes a **clean bootstrap, not a dead-end**, and the membership gap is understood:
  an IdC limitation that **any group-emitting upstream dissolves.**
- **Build implications** (the seam work to make A and B reachable):
  1. **Parametrize the upstream broker** — generalize the B2 `keycloak_saml_identity_provider` (AWS-SSO-specific)
     into an adapter selectable as `aws-sso | okta | entra | google` (SAML or OIDC).
  2. **Add the IdP-group → Keycloak-group mapper** — the membership mechanism for any group-emitting upstream.
  3. **Keep `_teams.hcl` + generators** as the access-model SoR; extend to AWS IdC account assignments.
  4. **Defer outbound SCIM** to the cases that need it (Keycloak→AWS in standalone mode; external SaaS) — the one
     fragile piece, now confined rather than on the critical path.
- **Costs:** more identity modes to document and test; Keycloak remains a **Tier-0 component** (ADR-053);
  outbound SCIM stays the weakest link but is scoped to scenarios B + SaaS.
- **Membership is still the prerequisite for B3/B4 delivering real authorization** (ADR-053): the claims are
  present but empty until a membership source is wired. This ADR names the default mechanism (group-claim mapper)
  that closes it the moment a group-emitting upstream is in place.
