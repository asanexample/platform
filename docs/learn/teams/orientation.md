# Learn: the Team — orientation

A Team is the first object you stand up on the platform and the one everything else hangs off. Onboarding one
is a single small file in git — and out of that file the platform derives the team's identity, its ownership,
and, above all, the *envelope*: the bound on everything the team's Products and Environments will ever be
allowed to ask for. This module is the procedure and the reference; the *concept* — why a Team is an envelope,
and how admission checks a claim against it — lives in [the domain model](../domain-model/orientation.md), and
the people-and-roles half lives in [Identity](../identity/orientation.md). This page doesn't re-teach either.
It covers the two things they don't: how the envelope is **enforced**, and what a Team **materializes into** —
and, just as important, what it doesn't.

**Audience:** platform engineers and team leads onboarding a team. Read
[the Team as an envelope](../domain-model/orientation.md#the-team-is-an-envelope) first for the concept, and
skim [Identity](../identity/orientation.md) for the SSO/roles half. This is the parent of
[Onboarding a Product](../products/orientation.md) — a Product must have a Team to own it.

## The question

Self-service is the whole promise: a team claims an environment, opens a PR, and gets a governed production
namespace without a ticket. But self-service without bounds is just a way to let anyone ask for anything — a
`pci` tier they aren't cleared for, a 200-CPU quota, a `prod` stage before they're ready. Something has to say
*this far and no further*, and it has to say it without a human reviewing every claim.

So where do a team's limits live, who sets them, and what makes them stick?

## One idea — set the boundary once

> A Team is a boundary you set once. Its envelope declares the outer edge of everything the team may ask for —
> which compliance tiers, which stages, how much quota, which self-service cloud engines — and every downstream
> request is checked against it at admission. Set it once, in git, and it holds for every environment the team
> ever claims.

That is what makes the self-service safe. The team moves on its own — claims environments, adds services,
ships — *inside* a fence a platform admin drew once and can read in one file. The bounds don't live in fifty
code reviews or in someone's memory; they live on the Team object, and the cluster checks every claim against
them. (The domain model walks a claim through that fence request by request —
[the envelope section](../domain-model/orientation.md#the-team-is-an-envelope) — so this module won't.)

## The record — a Team in git

Onboarding a Team is adding one file, `gitops/teams/<team>.yaml`. Here is `acme`'s, envelope and all (trimmed
for brevity — labels, comments, and a few optional fields elided; the [reference](reference.md) has the full
field-by-field schema):

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Team
metadata:
  name: acme
spec:
  ssoGroup: Dev-acme               # the IDENTITY half — the IdP/Keycloak group this team maps to
  envelope:                        # the GOVERNANCE half — the bound on everything the team may ask for
    allowedTiers:  [standard]      # compliance tiers an Environment may request
    allowedStages: [dev, test, uat, staging, prod]
    quotaCap: { cpu: "8", memory: 16Gi, pods: 40 }   # per-Environment ResourceQuota ceiling
    budget:   { monthlyUSD: 2000 }                    # cost guardrail (surfaced/alerted, not hard-enforced)
    resources:                     # self-service cloud resources (S3 / SQS / SNS / DynamoDB)
      allowedEngines:  [s3, sqs, sns, dynamodb]
      maxPerEnvironment: 10
```

Two halves, and that's the whole shape worth holding in your head. `spec.ssoGroup` is *who the team is* — the
identity-provider group whose members are the team (see [Identity](../identity/orientation.md)).
`spec.envelope` is *what the team may do* — the fence. Nearly everything the platform builds for the team
derives from those two fields; a couple of optional records — incident routing (`spec.slack` / `spec.pagerduty`,
which drive the triage agent and the team's PagerDuty on-call, ADR-084) — ride on the same object.

`kind: Team` is a real cluster CRD — cluster-scoped and data-only; it provisions nothing, it's just the
admission-relevant mirror of the envelope. But the file in git is the source of truth: ArgoCD syncs it into the
cluster as a read-only record, and several Terragrunt units read the same YAML directly. One record, read in
both worlds.

## What onboarding materializes — and what stays per-Product

Merge that file and the platform converges a handful of things off it, each keyed on the one Team
(`metadata.name`):

- **A Keycloak group** — one group per Team (`Dev-acme`), the SSO identity the team signs in as; apps read the
  bare group name from the token. (Plumbing: [Identity](../identity/orientation.md).)
- **A GitHub org team** — the human *ownership* grant. When the team owns a Product, this org team is granted
  `push` on that product's repo ([ADR-072](../../adrs/072-app-repo-naming-and-team-ownership.md)). One caveat
  worth keeping: org-team membership never rides in the CI token, so it carries **no** supply-chain authority —
  image trust always anchors on the repo, never on team membership.
- **A Backstage group** — the Team projected into the developer portal's catalog, so ownership shows up where
  people browse.
- **The enforced envelope** — the fence above, now live at the cluster door: once the Team record is synced,
  admission knows the team's bounds and starts checking every Environment claim against them.

Here's the line that's most of understanding the model: these are the things that are genuinely *per team*. A
team's registries, CI push roles, image-verify policies, and workload IAM roles are **per Product**, not per
Team — they're named `<team>-<product>`, where `<team>` is only a coordinate in the name, not a thing that
fans out once per team. Onboarding the Team gives you identity, ownership, and the governance envelope; the
product footprint comes later, when the team [onboards a Product](../products/orientation.md).

## The envelope is a contract, enforced in three places

The envelope isn't documentation — it's a contract the platform checks. When an Environment is claimed, its
request (tier, stage, quota, residency, resource engines) is compared against the owning Team's envelope, and
an over-the-line claim is **rejected**, not merely flagged:

- **At admission** — Kyverno's `restrict-environment-envelope` policy reads the projected Team CR and denies
  any Environment claim whose tier, stage, quota, residency, or self-service engine falls outside the envelope.
  This is the real enforcement point.
- **In the PR** — the gitops gate runs the *same* checks before merge, against the trusted base copy of the
  Team file, so a bad claim fails in CI instead of at the cluster.
- **At materialization** — the Crossplane Composition then renders the (already-bounded) quota into a real
  `ResourceQuota` in the environment's namespace. It trusts what passed; the bounding happened upstream.

And because the CRD schema can't bound the *envelope itself* — nothing in the CRD stops someone writing
`quotaCap: { cpu: "10000" }` — onboarding a Team goes through its own **Teams gate** on the PR. It enforces the
platform-max ceilings, blocks mapping a tenant to a privileged SSO group, and refuses to delete a Team while
environments still reference it. A Team grants power, so its PR is **always human-reviewed** — it never
auto-merges.

## Where a Team fits

A Team is the root of the ownership tree ([domain model](../domain-model/orientation.md)):

- A **Team** owns Products and declares the envelope that bounds them.
- A **Product** is one application the team owns ([Onboarding a Product](../products/orientation.md)).
- An **Environment** is a Product at a stage (`acme-shop-dev`), claimed within the envelope
  ([Environment API](../environment-api/orientation.md)).

Onboard the Team first: a Product PR is rejected if its Team doesn't exist yet, and an Environment claim is
rejected if the envelope doesn't allow it.

## Go deeper

- **Onboard one yourself:** [How-to: onboard a new Team](how-to-onboard-a-team.md) — the Backstage scaffolder
  path and the hand-authored PR, step by step.
- The `Team` CR schema, field by field, with the honest gotchas: the [Reference](reference.md).
- The concept this module builds on: [the Team as an envelope](../domain-model/orientation.md#the-team-is-an-envelope) ·
  the people-and-roles half: [Identity](../identity/orientation.md).
- Why it's shaped this way: [ADR-063](../../adrs/063-team-as-first-class-git-object.md) (Team as a first-class
  git object) · [ADR-067](../../adrs/067-idp-domain-model.md) (the domain model) ·
  [ADR-072](../../adrs/072-app-repo-naming-and-team-ownership.md) (org-Team ownership).
