# ADR-062: Self-Service Tenant Provisioning (Backstage + GitOps) & Its Security Model

**Date:** 2026-06-09
**Status:** Accepted — built + live (Phase 3, #278–285). The delivery surface for the [ADR-049](049-tenant-model-team-tenant-zone.md)
multi-tenancy model; lands with (and after) the rebuild's tenant-api-v2 step. Builds on
[ADR-046](046-back-stack-for-developer-self-service.md) (BACK stack),
[ADR-053](053-identity-and-cross-system-authorization-strategy.md) (access-as-code),
[ADR-051](051-backstage-developer-portal.md) (portal), and the Backstage RBAC shipped in #197.

## Context

[ADR-049](049-tenant-model-team-tenant-zone.md) + [tenant-api-v2.md](../architecture/tenant-api-v2.md) define
*what* a tenant is and that **a developer/team authors only the Tenant claim** — i.e. tenancy is
**self-service within a Team envelope**, with the envelope enforced at admission by Kyverno. What they do
*not* specify is *how* a team actually self-serves from the portal: the model says "the developer authors a
Tenant claim," never the delivery path, the authorization split, or the controls that make letting teams open
changes to the platform repo safe.

That delivery path is BACK-stack **Phase 3** (ADR-046/051). It is also, explicitly, the **"security cliff"**
the portal ADRs flagged: Phase 2 ran a *read-only* GitHub App and a read-only portal on purpose. Phase 3 needs
**write** — opening PRs that provision tenants and (for admins) Teams — and **a self-service PR-with-automerge
flow is a privilege-delegation engine.** The security model is therefore not an addendum to this ADR; it *is*
the decision.

Two non-negotiables frame it: nothing **auto-applies** (everything flows through git + ArgoCD, reviewed by
CI), and the platform team's leverage is in **setting Teams/envelopes**, not gatekeeping every Tenant — that's
the whole point of encoding the guardrail once (ADR-049) so per-tenant approval can be safely delegated.

## Decision

### 1. Two flows, two authorization scopes

| Flow | Who | Authoring | Merge | Guardrail |
|------|-----|-----------|-------|-----------|
| **New Team** | platform admins only | a `Team` object ([ADR-063](063-team-as-first-class-git-object.md)) — sets the envelope | **human review** (never automerge) | it *grants* an envelope; a privilege grant warrants review |
| **New Tenant / App** | a team member, **scoped to their own team** | a `Tenant` claim within the Team's envelope | **automerge when in-envelope + checks pass** | Kyverno envelope (admission) + the CI gate (§3) |

Backstage RBAC scopes *who may run which template for which team*: the permission policy from #197 already
keys on the user's `ownershipEntityRefs` (their Keycloak group → `group:default/<team>`). `New Tenant` is
gated to the requesting member's own team; `New Team` is gated to `platform-admins`. This is the **first
guardrail** (who can *request*); the envelope is the **second** (whether the *request* is in bounds) — defence
in depth, neither sufficient alone.

### 2. Delivery is PR-with-automerge — Tenants only

A `New Tenant` run opens a PR adding the team's Tenant claim; CI validates it (§3); if it passes **and** the
diff is in-bounds, it **auto-merges** and ArgoCD syncs → the Composition reconciles → Kyverno admits. The
envelope is the safety net that makes automerge safe: a claim that exceeds the envelope cannot be admitted even
if it merged. `New Team` never automerges (§1).

We chose PR-with-automerge over **direct-apply** (bypasses git history/review; the envelope would be the *only*
gate) and over **PR-with-human-review** (audited but reintroduces a per-tenant bottleneck, defeating
self-service). PR-with-automerge keeps everything in git, reviewed by deterministic CI, with no human in the
per-tenant loop — *conditional on the CI gate being trustworthy*, which §3–§4 ensure.

### 3. The CI gate (what makes automerge safe)

Extends the existing **"Kyverno Shift-Left (dogfood)"** CI job and the `.tenant-api-tests/render/` Composition
render tests. A Tenant PR auto-merges only if **all** pass:

1. **Envelope dry-run** — `kyverno apply` the proposed claim against the team's projected `Team` CR +
   `restrict-tenant-envelope`. Over-envelope (tier/env/location/quota) → fail. *The key check.*
2. **Claim schema** — `kubeconform` against the XRD.
3. **Composition render** — render the Composition against the new claim; must produce valid output.
4. **Path/diff restriction** — the diff touches **only** the allowed claim path(s)
   (`gitops/tenant-claims/…/<team>/…`). Any other path → automerge denied, human review required (see §4).
5. **Aggregate-quota** — `sum(team's existing tenant quotas + this one) ≤ Team.quotaCap`, and tenant-count ≤ a
   per-team cap. CI is *stateful* (it reads every claim file), so it hard-gates what admission cannot: the
   team-aggregate cap is "report-first" at runtime (tenant-api-v2.md) — CI makes it a *blocking* check.
6. **Author == team** — the PR's claim `spec.team` matches the requesting member's team (a CI backstop to the
   Backstage RBAC scoping in §1).

### 4. Security model

These are load-bearing controls, not hardening niceties:

- **IAM escalation boundary (critical).** A Tenant claim authors `apps.<app>.permissions.aws.policyStatements`.
  tenant-api-v2 *names* a "deny-escalation boundary"; the delivery **enforces** it two ways: every minted role
  carries an **AWS permissions boundary** (a hard ceiling the inline policy cannot exceed), **and** a
  Kyverno/CI check validates requested statements ⊆ an allow-set (no `iam:*`, no `sts:AssumeRole` to arbitrary
  ARNs, no wildcards on sensitive services). Self-service IAM without this is self-grant-anything.
- **Automerge path/diff restriction (critical).** GitHub Apps scope by **repo, not path** — the write App
  *can* edit any file in the platform repo. The automerge gate (§3.4) therefore hard-requires the diff to touch
  only claim paths; a PR touching policy/IAM/workflow/module files falls to human review. Plus **CODEOWNERS**
  on `scaffolder/`, the templates, and the sensitive infra paths.
- **CI-gate integrity (critical).** The gate workflow runs from the **protected base branch** (not the PR's
  copy) and is a GitHub **required status check**; automerge requires it to *pass*. This blocks the classic
  `pull_request` self-tampering — a PR cannot edit the very workflow that judges it.
- **Audit attribution.** App-authored PRs otherwise read as the bot. The scaffolder stamps the **requesting
  Backstage user** into the claim annotation + the commit trailer for non-repudiation.
- **Least-privilege, separate GitHub write App (§5).**

### 5. The GitHub write App (the "cliff")

A **separate** GitHub App — never a widening of the read-only discovery App (ADR-051) — scoped to **only**
`asanexample/platform`, permissions **Contents + Pull Requests: read/write only** (no Administration, no
branch-protection bypass; it opens PRs, it does not merge — automerge is GitHub's, gated by required checks).
Key stored in Secrets Manager `platform/backstage/scaffolder-github-app`, delivered via the existing
ExternalSecret path. Because the App can touch any file in the repo, the §4 path-restriction + CI-integrity
controls are the compensating controls if the key leaks; Backstage is treated as a **high-value target**
accordingly (its other creds — ArgoCD, K8s — stay read-only).

### 6. Orchestration tooling posture (context)

We deliver this on the existing **Crossplane + ArgoCD + Kyverno + Backstage** stack — no new orchestrator.
**Kratix** is not adopted (it overlaps Crossplane's "platform API + fulfilment"; revisit only for large fleet
scheduling or a broad capability marketplace). **Score** is deferred to the *App* golden path (a workload-layer
spec; it would generate Kyverno-compliant manifests by construction). That the automerge gate is buildable on
Kyverno-in-CI — which we already run — is itself evidence the existing stack suffices.

## Consequences

- Teams provision tenants without platform-team involvement; the platform team's control point becomes Team +
  envelope authoring and the guardrails — the intended IDP shape.
- The security surface is real and concentrated in the write App + automerge gate; the controls above are
  mandatory before any write-enabled code ships.
- **Deprovisioning (built, #283 + Deprovision Product):** the safe teardown flow is a **two-step, reversible-
  until-the-last-step** model — *decommission* (a reversible `spec.lifecycle.phase` suspend) then, after a grace
  window, *purge* (delete the claim). It exists per-Environment (*Deprovision Environment*) and per-Product
  (*Deprovision Product*, which fans out over every Environment). Runbooks:
  `environment-deprovisioning.md`, `product-deprovisioning.md`.
  - **Deletion-authorship evolution:** the original #283 rule was "the scaffolder never authors a deletion — the
    hard-delete is a human PR." We've since relocated the control from **authorship** to **approval**: the
    scaffolder may author a deletion PR, but only on a sanctioned `product/purge-*` / `environment/purge-*`
    branch, and the gitops Gate still requires a current-SHA **admin/maintainer approval (≠ author)** — plus the
    **release-approver** if a **prod** environment is in the bundle — and **never auto-merges** it. This is
    strictly safer per UX (no hand-run `git rm`) and equally safe per control (a bot can't self-approve; the
    decommission-first + completeness guards are author-agnostic). The **promote** App may never author a deletion.
- **Deferred / separate:** **cost guardrails** (the upcoming cost-management effort — this work leaves the
  `quotaCap`/aggregate seam); opening `New Tenant` to non-admins is the *intended* model but is gated on the
  rebuild implementing the Team/Tenant split and the RBAC scoping.

## Relationships

- **Implements the delivery surface for** [ADR-049](049-tenant-model-team-tenant-zone.md) (Team/Tenant model)
  and is **the BACK-stack Phase 3** of [ADR-046](046-back-stack-for-developer-self-service.md).
- **Consumes** [ADR-053](053-identity-and-cross-system-authorization-strategy.md) (the Backstage RBAC / Keycloak
  group identity, #197) for the per-team scoping.
- **Authors the object defined in** [ADR-063](063-team-as-first-class-git-object.md) (Team) and the Tenant
  claim of [tenant-api-v2.md](../architecture/tenant-api-v2.md).
- **Visibility** of the resulting provisioning is [ADR-064](064-backstage-provisioning-visibility.md).
- **Builds on** [ADR-014](014-kyverno-as-policy-engine.md) (Kyverno admission), the envelope guardrail of
  ADR-049, and [ADR-036](036-github-actions-oidc-federation.md) (GitHub identity patterns).
- Touches the `backstage`, `crossplane`, `policy`, `github-oidc`, and `argocd-apps` units; the
  `asanexample/backstage` app; and the platform repo's CI.
