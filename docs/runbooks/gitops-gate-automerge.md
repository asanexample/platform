# Runbook: Environment-Claims PR Automerge (the Environment Claims Gate)

> **Purpose:** how self-service environment provisioning merges without a human (ADR-062 §2–4, #281): the
> Backstage **New Environment** template opens a PR via the scaffolder write App; the **gitops Gate**
> (`.github/workflows/gitops-gate.yml`) validates it deterministically and arms GitHub auto-merge;
> GitHub merges when every required check passes; ArgoCD syncs the claim; Crossplane provisions; Kyverno
> envelope enforcement at admission is the runtime backstop.
>
> **Last reviewed:** 2026-06-09

---

## ⚠️ v3 supersedes this (2026-06-12)

The v2 Environment Claims Gate was **retired at the v3 cutover**; its automerge + decommission-first deletion model
now lives in the **`gitops Gate`** (`.github/workflows/gitops-gate.yml`), which gates the registry
surfaces (`gitops/products/**`, `gitops/environments/**`). Same model — see that workflow's header decision
table. What's different for v3:

- **Scaffolder templates:** New Product, New Environment, Deprovision (the v2 "New Tenant" template is
  retired). A bot-authored,
  registry-only, non-deletion, fully-validated PR arms auto-merge; deletions are decommission-first
  (`spec.lifecycle.phase: decommissioning` on base) + a current-SHA admin approval.
- **Deletion guards (`validate-deletions.sh`, two checks):**
  - **Environment** — decommission-first: a `gitops/environments/**` claim may only be deleted if it was
    already set to `spec.lifecycle.phase: decommissioning` on base (a prior, reversible Deprovision PR).
  - **Product** — completeness: a `gitops/products/<team>/<product>.yaml` may only be deleted once it has **no
    remaining Environments** (none under `gitops/environments/<team>/<product>/` on base that this PR doesn't
    also delete). Deleting a Product with live Environments would orphan its per-Product OIDC role / ECR /
    ApplicationSet and break the survivors' Composition render. Order: decommission + remove every Environment
    first, then remove the Product (a single PR may bundle the Product with its already-decommissioned
    Environments). Unit-tested by `.github/scripts/gitops-gate/test-validate-deletions.sh`.
- **Required checks (activation):** update `main`'s branch protection — **add** `gitops Gate` +
  `gitops Approval`, **remove** the retired `Environment Claims Gate` + `Kyverno Shift-Left (dogfood)`. Until
  `gitops Approval` is a required check, a registry deletion isn't gated on the approval (the gate still
  posts the status, but branch protection isn't enforcing it). See the updated settings block below.

The rest of this runbook (CI-gate integrity, threat model, repo settings rationale) applies unchanged — read
"claim" as the Environment/Product registry files and "Environment Claims Gate" as "gitops Gate".

---

## Decision table

| PR author | Diff | Outcome |
|---|---|---|
| scaffolder App | only `gitops/environments/**` (+ `gitops/products/**`, `gitops/releases/**`) adds/modifies, all checks pass | gate green, **auto-merge armed** |
| scaffolder App | same, any check fails | gate red, no merge |
| scaffolder App | anything else (New Team PRs, or a compromised key straying) | gate red until an **admin approves the current head SHA**; never auto-armed |
| scaffolder App | deletes/renames a claim | gate red (the hard-delete is a human, reviewed PR — ADR-062 #283; use the Deprovision template to decommission first) |
| human | deletes a claim | allowed only if the environment is `decommissioning` on base AND an admin approves the current SHA; never auto-armed (see [environment-deprovisioning.md](environment-deprovisioning.md)) |
| human | touches claims | claims fully validated; **never auto-armed** |
| human | no claims | gate trivially green |

## What the gate checks (per changed claim)

1. **Shape/hygiene** (untrusted data): single-doc YAML ≤64KB, no symlinks, kind/apiVersion, name regexes
   (`^[a-z][a-z0-9]{1,15}$`), `metadata.name == <team>-<name>-<env>` ≤63 chars, filename convention for
   new files.
2. **Team exists on BASE** `gitops/teams/` — teams are never read from the PR, so a team+claim-in-one-PR
   privilege escalation is structurally impossible.
3. **Envelope dry-run** — the claim (normalized with the XRD's schema defaults, extracted from the BASE
   XRD) is evaluated offline against `restrict-environment-envelope` with the BASE Team CR stubbed via kyverno
   `globalValues` (same harness pattern as `infra/modules/crossplane/.kyverno-tests/`).
4. **Schema** — `crossplane beta validate` against the BASE XRD.
5. **Composition render** — `crossplane render` with the BASE Composition v2 + the
   `.environment-api-tests/render/` fixtures must succeed.
6. **IAM deny-set** (ADR-062 §4, #282) — `spec.services.*.permissions.aws.policyStatements` is allowed but
   **deny-set-validated**: any action whose lowercased service prefix is a sensitive service
   (`iam`/`sts`/`organizations`/`account`), or a bare `*`/`*:*` wildcard, is rejected. The check lives in the
   `restrict-environment-envelope` Kyverno policy (`policystatements-no-escalation` rule), so the envelope dry-run
   above covers it — and every minted role is additionally capped by the **AWS permissions boundary** (the hard
   runtime ceiling, already live: `environment-permissions-boundary-<cluster>`, attached by the Composition,
   un-strippable by the provisioner). The deny-set is intentionally ⊇ the boundary. **Not resource-scoped:**
   `s3:*` on `resources: ["*"]` (all account buckets) passes — broad but not escalation; per-team resource
   prefixes are a documented follow-up, not #282.
7. **Requester attribution** — scaffolder-authored claims carry the `platform.refplat.org/requested-by`
   annotation (ADR-062 §4). Note this is **not gate-enforced** in v3 (presence is advisory metadata, not a
   blocking check — see threat model).
8. **Aggregate quota** (v2-only / not implemented in v3): the retired Environment Claims Gate summed a team's
   claim quotas against `Team.envelope.quotaCap` and capped environment count at `MAX_TENANTS_PER_TEAM` (10).
   **The v3 `gitops Gate` does not implement this** — there is no aggregate-sum or env-count logic (and no
   `MAX_TENANTS_PER_TEAM` var) in `.github/scripts/gitops-gate/*.sh`. The runtime aggregate check remains
   report-first; a CI-time aggregate gate is future work.

## CI-gate integrity (why a PR can't cheat)

- The workflow triggers on `pull_request_target` + `pull_request_review`, so the gate definition and all
  scripts under `.github/scripts/gitops-gate/` run from the **protected base branch** — a PR editing the
  gate is judged by the *current* gate, not its own copy.
- The PR's content is checked out sparse (`gitops/` registries only), credential-free, and treated as
  data: nothing from the head checkout is ever executed or templated.
- **Stale approvals don't count**: for App-authored non-claim PRs, only an admin/maintainer approval whose
  `commit_id` equals the current head SHA passes the gate — an approve-then-push sequence goes red again
  (the in-gate equivalent of dismiss-stale-reviews, which plain branch protection can't give us without a
  required-review rule).
- Auto-merge is armed with `gh pr merge --auto`; GitHub performs the merge only once **all** required
  checks pass, so the gate racing the rest of CI is harmless.

## Repo settings (one-time; current state after #281)

```bash
# 1. Allow auto-merge at the repo level
gh api -X PATCH repos/asanexample/platform -F allow_auto_merge=true

# 2. Protect main: required status checks only — NO required reviews (see rationale below)
gh api -X PUT repos/asanexample/platform/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": { "strict": false, "checks": [
    {"context": "OpenTofu Format"}, {"context": "OpenTofu Validate"},
    {"context": "Terragrunt HCL Format"}, {"context": "Markdown Lint"},
    {"context": "Kyverno Policy Test"},
    {"context": "Environment API Schema"}, {"context": "Environment Composition Render"},
    {"context": "TFLint"}, {"context": "Trivy (IaC + deps)"}, {"context": "Semgrep (SAST)"},
    {"context": "gitops Gate"}, {"context": "gitops Approval"} ] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

**Why no required reviews:** GitHub cannot require reviews per-path; any global review requirement would
block claim PRs from auto-merging, defeating self-service. The compensating controls are the gate (CI),
the envelope (admission), and the review-aware gate rule for non-claim App PRs. `enforce_admins=false`
keeps the admin bypass for operational PRs.

**Order matters:** only add the `gitops Gate` / `gitops Approval` checks to required checks after the workflow
exists on `main`, or every open PR deadlocks waiting for a check that never reports.

## Threat model / residual risks (v1, explicit)

- **Compromised write-App key** can author **within-envelope, cross-team** claims that automerge: the App
  bypasses the portal templates, so the server-side team-membership check doesn't bind it, and the
  `requested-by` annotation is presence-only. Blast radius is bounded by every team's envelope, the IAM
  lockout, and the claims-only path restriction (anything else needs an admin approval of the exact SHA).
  Mitigations: key custody/rotation (`backstage-scaffolder-github-app.md`), and — future hardening — a
  portal-signed claim attestation the gate verifies, making the stamp non-spoofable. Note the IAM blast radius
  is bounded regardless: the policyStatements deny-set (above) + the un-strippable AWS permissions boundary cap
  what any claimed role can do.
- **Merges via auto-merge don't trigger `push: main` workflows** (GITHUB_TOKEN actor): ci.yml's main-push
  run is skipped for automerged claims. Provisioning is unaffected (ArgoCD pulls git directly); the same
  validations already ran on the PR. Swap to an App-token-armed merge later if main-branch CI records
  matter.
- **CODEOWNERS is signal, not enforcement** (no required-review rule). The collaborator set is the actual
  write control; `.github/` changes are protected from PR self-tampering by `pull_request_target`, and
  from the App by the review-aware gate rule.

## Post-merge consumers (NOT automated by the gate)

A new claim **provisions the environment** (namespace, quota, policies, Pod Identity, ECR) via ArgoCD →
Crossplane with zero further action. But a claim introducing a **new app/repo** still needs the delivery
consumers applied (they derive from the claims): `policy` (preprod), `argocd-apps`, `github-oidc` —
see `environment-onboarding.md`. Candidate for the #305 terragrunt-in-CI converge job (phase 1.5: trigger on
`gitops/environments/**`).

## Sibling gates: People & Roles registries

The gitops Gate guards the **environment/product** registries. Two sibling gates guard the
**workforce identity** registries with the same `pull_request_target` integrity model (the gate
definition + scripts run from the protected base branch; the PR's CRs are checked out sparse,
credential-free, and read strictly as YAML data with `yq`). Both run on **every** PR (no paths
filter) so they can be required status checks, and short-circuit to trivially green when their tree
isn't touched. **No live provisioning yet** — #888/#889 project the roster downstream; these gates
validate and route approval.

- **People Gate** (`.github/workflows/people-gate.yml`, `.github/scripts/people-gate/`) — validates
  `gitops/people/**` Person CRs: schema shape, the role catalog, team-ref integrity, and anchor
  uniqueness (`validate-people.sh`). Unlike the environment gate, People CRs **grant access** and stay
  deliberately human-reviewed: `publish-verdict.sh` routes approval **by content** to the **"People
  Approval"** commit status — a *team* grant needs that team's lead; a *platform* grant or an
  *offboarding* needs an access-admin. The approver sets are read only from base, so a
  team+grant-in-one-PR escalation is structurally impossible.
- **Roles Gate** (`.github/workflows/roles-gate.yml`, `.github/scripts/roles-gate/`) — validates
  `gitops/roles/**` role-catalog CRs: schema shape, the reach/power/mode/risk enums, the IC/Keycloak
  projection mappings, and the deletion guard (`validate-roles.sh`). Because changing a role
  re-permissions everyone who holds it, it enforces **meta-governance**: the sticky comment reports the
  **blast radius** (Person grants referencing each changed role) and every catalog change is routed to
  an admin/maintainer approval via the **"Roles Approval"** commit status (two-person control).

Both publish a sticky PR comment, are last-write-wins per `(sha, context)` so they survive the
`pull_request_target`→`pull_request_review` handoff, and have script-level unit tests
(`test-validate-*.sh`, `test-publish-verdict.sh`). On a single-admin project the `SOLO_MAINTAINER`
repo var lets an admin author self-attest. To make them binding, add **"People Gate" / "People
Approval"** and **"Roles Gate" / "Roles Approval"** to `main`'s required checks (same ordering caveat
as above — only after the workflows exist on `main`).

## Local testing

```bash
# All gate scripts run locally (yq v4, helm, kyverno 1.18, crossplane CLI; docker for the render check).
# validate-environments.sh reads BASE_DIR / HEAD_DIR / ENVIRONMENT_FILES / IAM_SENSITIVE (NOT CHANGED_FILES /
# BOT_AUTHOR / RENDER_CHECK — those are unread and would silently pass nothing):
BASE_DIR=$PWD HEAD_DIR=$PWD \
  ENVIRONMENT_FILES="gitops/environments/alpha/shop/dev.yaml" \
  .github/scripts/gitops-gate/validate-environments.sh
# Other validators: validate-products.sh, validate-releases.sh, validate-deletions.sh
#   (+ classify-diff.sh / render-environments.sh / publish-verdict.sh — see .github/scripts/gitops-gate/)
```
