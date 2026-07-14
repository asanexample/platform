# Teams — the ownership envelope, and how to stand one up

A **Team** is the top-level owner on the platform: one small git file
(`gitops/teams/<team>.yaml`) that carries a team's identity — its SSO group — and its *envelope*, the
bound on everything the team's Products and Environments are ever allowed to ask for. This module is the
**procedure** for standing one up, and a **reference** for the Team CR.

It's deliberately lean, because two other modules already own the *concept*. Why a Team is an envelope,
and how admission checks a claim against it, lives in
[the domain model](../domain-model/orientation.md) — the people-and-roles half (SSO groups, role
projection, who's actually *in* a team) lives in [Identity](../identity/orientation.md). This module
doesn't re-teach either. It covers the two things they don't: how the envelope is *enforced*, and what a
Team *materializes* into — and, just as important, what it doesn't.

**Audience:** platform engineers and team leads onboarding a team. Read
[the domain model](../domain-model/orientation.md) first for the concept, and skim
[Identity](../identity/orientation.md) for the SSO/roles half. Already fluent? Go straight to the
[Reference](reference.md).

## The module

| Doc | What it covers |
| --- | --- |
| **[Orientation](orientation.md)** | The one idea the domain model doesn't carry: the envelope's three enforcement layers (Kyverno admission, the gitops + Teams gates, the Composition's ResourceQuota) and the per-Team-vs-per-Product derivation boundary — what a Team fans out to, and what stays scoped to a Product. |
| **[How-to: onboard a team](how-to-onboard-a-team.md)** | The playbook — the Backstage scaffolder path and the hand-authored-PR path, the admin gate, and what apply-on-merge converges (the Keycloak group, the GitHub org team, admission). |
| **[Reference](reference.md)** | The `Team` CR schema field-by-field — `spec.ssoGroup`, the `spec.envelope` bounds, and the identity/routing fields — with real values and the honest gotchas (the stale scaffolder skeleton, the DeveloperAccess role that's designed-not-built). |

## Go deeper

- The concept this module builds on: [the domain model](../domain-model/orientation.md) · the
  people-and-roles half: [Identity](../identity/orientation.md).
