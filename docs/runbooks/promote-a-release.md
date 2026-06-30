# Runbook: Promote a Release

> **Purpose:** how to move a signed image up the stage ladder (dev → test → uat → staging → prod) — on demand or
> automatically — and how a **release-approver** approves a gated prod promotion. Promotion moves a **digest**,
> never a rebuild ([ADR-067 §8](../adrs/067-idp-domain-model.md), [ADR-071](../adrs/071-digest-promotion-via-control-plane.md)).
>
> **Last reviewed:** 2026-06-15

**Related:**
[Promotion & Release](../architecture/promotion-and-release.md) (architecture) ·
[Delivery Pipeline](../architecture/delivery-pipeline.md) ·
[Ship a Service](../ship-a-service.md) ·
[Environment-Claims PR Automerge](gitops-gate-automerge.md) ·
[Promote GitHub App](promote-github-app.md).

---

## Contents

- [Concepts in 30 seconds](#concepts-in-30-seconds)
- [Promote on demand](#promote-on-demand)
- [How auto-promotion works (≤ staging)](#how-auto-promotion-works--staging)
- [Approve a prod promotion (release-approver)](#approve-a-prod-promotion-release-approver)
- [Add or change a release-approver](#add-or-change-a-release-approver)
- [Troubleshooting](#troubleshooting)

---

## Concepts in 30 seconds

- A **Release** (`gitops/releases/<team>/<product>/<stage>.yaml`, in the **platform** repo) names the digest
  deployed at one stage. The delivery ApplicationSet reads it and runs that digest.
- **Promotion = write the lower stage's digest into the next stage's Release.** A promote-bot PR does this; the
  gitops Gate validates and (≤ staging) auto-merges it.
- **prod is gated** — it merges only after a **release-approver** (≠ the PR author) approves.

## Promote on demand

**From Backstage (preferred).** Open the **Request Promotion** template, pick the Product, Service, the
*from* stage **and** the *to* (target) stage — both are required. It resolves the *from* stage's running digest,
renders the *to* stage's Release, and opens the PR. (The *to* stage must already have an Environment.)

**From the app repo.** Run the app's `promote.yml` via **Actions → Run workflow** (`workflow_dispatch`), giving
both the `from_stage` and `to_stage` inputs. The source digest is resolved after clone — you don't paste a digest.

Either way the result is an `asanexample-promote[bot]` Release PR on the platform repo. For test/uat/staging it
auto-merges once green; for prod see [below](#approve-a-prod-promotion-release-approver).

## How auto-promotion works (≤ staging)

A scheduled reconciler ([`.github/workflows/auto-promote.yml`](../../.github/workflows/auto-promote.yml)) walks
each Product's ladder and advances the digest **one rung per run**, but only `dev→test→uat→staging` — **prod is
never auto-promoted**. A rung is promoted only when the **lower** stage's ArgoCD Application is **`Synced` +
`Healthy`** (the digest is actually running and settled). It is idempotent and won't reopen a promotion already in
flight. You usually don't touch it — it keeps the lower stages current on their own.

## Approve a prod promotion (release-approver)

You'll be asked to review a Release PR titled like `promote: <team>-<product>-prod <service> (staging→prod)`.
(The `-> <digest>` form is the **commit message**, not the PR title.)

1. Confirm you are a **release-approver** for that Product/Team and that **you did not author** the PR (the gate
   excludes the author).
2. Verify it's a pure promotion: it should change only `gitops/releases/<team>/<product>/prod.yaml`, and the
   digest should match what's currently running at **staging**.
3. **Approve** the PR (GitHub review → Approve). The gate re-evaluates and flips the **`gitops Approval`** status
   to success; the PR then merges and delivery rolls the digest to prod.

For **`pci`/`hipaa`** environments, **two distinct** release-approvers must approve.

## Add or change a release-approver

The approver set is **derived from Person grants** (ADR-090 — the single source of truth for role-holding):
whoever holds the `release-approver` `WorkforceRole` for the team. To add or change an approver, edit the
**Person** record:

- Give someone the role: add `{ role: release-approver, team: <team> }` to their `spec.grants` in
  `gitops/people/<person>.yaml` (they must have a `spec.handles.github`). Remove the grant to revoke it.
- The gate derives the required-reviewer set = the github handles of the People holding `release-approver` for
  that team (case-insensitive, author excluded).

Editing a Person's grants is **itself privileged** (the two-step guard): the change is held by the **People
Gate** (`People Approval`) and needs an **admin/team-lead** approval (≠ author). This is what stops *"add
myself, then approve my own prod."* (`spec.roles.releaseApprover` on the Team/Product is **retired** — ADR-090.)

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| **`gitops Approval` = failure: "no release-approver configured"** | No Person holds `release-approver` for the team; prod is **fail-closed** | Grant the role to someone (see above) and merge that (gated) People PR first |
| **`gitops Approval` stays failure after you approved** | You authored the PR, or you're not in the set, or the review isn't on the **current** HEAD | Have a *different* configured approver review the latest commit |
| **`pci`/`hipaa` prod won't merge with one approval** | Regulated tiers need **≥2 distinct** approvers | Get a second release-approver to approve |
| **Gate rejects: no sibling Environment for the target stage** | Promoting to a stage that has no Environment | Create the Environment first (Backstage → New Environment) |
| **Promote PR is empty / "already pinned"** | The target stage already carries that digest (idempotent) | Nothing to do — it's already there |
| **Auto-promotion isn't advancing a rung** | The lower stage's Application isn't `Synced` + `Healthy` | Fix the lower deployment; the reconciler advances once it settles |
| **prod PR auto-merged without approval** | Should never happen — would mean the prod path didn't match | Check `classify-diff.sh` / the gate logs; the prod-release regex must match the file path |

→ Promote App / bot token issues: [Promote GitHub App](promote-github-app.md). Gate auto-merge model:
[Environment-Claims PR Automerge](gitops-gate-automerge.md).
