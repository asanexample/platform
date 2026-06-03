# ADR-050: Shared `build-sign` Reusable Workflow + Shared-Signer Policy Model

**Date:** 2026-06-03

**Status:** Accepted — extends [ADR-042](042-isolated-build-provenance-slsa-l3.md) (isolated provenance) and
[ADR-036](036-github-actions-oidc-federation.md) (GitHub Actions OIDC federation). **Live on preprod
(2026-06-03): app-alpha and app-bravo migrated to thin callers; the platform policy accepts the shared-signer
identity in Enforce.** Supersedes-in-part the per-app-`deploy.yml`-identity framing of
[`../architecture/cosign-image-signing.md`](../architecture/cosign-image-signing.md).

## Context

ADR-042 moved **provenance** signing into an isolated, app-team-unwritable reusable workflow
(`asanexample/trusted-ci/slsa-provenance.yml`). But the rest of each app's CI — **build → ECR push → cosign
sign → SBOM** — was still ~130 lines of `deploy.yml` + ~100 lines of `preview.yml` **copied into every app
repo** (`app-alpha` as the reference). Onboarding a new app (or a new team) meant copy-pasting that, and a
fix to the signing logic meant editing every app repo. That doesn't scale to many apps/teams and is exactly
the duplication a self-service platform should remove.

Almost none of that CI is app-specific: `docker buildx` of a Dockerfile, `cosign sign` by digest, and a Syft
SBOM are identical for any containerized app regardless of language. **The Dockerfile is the only
language/framework-specific surface** — and it's inherently the app's to own.

Two forces shaped the decision:

- **Not all apps are the same.** Some will need bespoke builds (exotic toolchains, multi-image, non-Docker).
  The abstraction must not be a straitjacket.
- **The signing identity is security-critical.** Whatever signs image+SBOM must be uncompromisable by app
  teams, the same way `slsa-provenance.yml` already is for provenance.

## Decision

**1. Abstract the supply-chain backbone into a shared reusable workflow.** Add
`asanexample/trusted-ci/.github/workflows/build-sign.yml` (`on: workflow_call`): build from the app's
Dockerfile → push to `team-<team>/<app>` ECR (team derived from the `app-<team>` repo name, never a caller
input) → `cosign sign` the digest → attach a CycloneDX SBOM. It assumes the per-team
`github-actions-ecr-push-<team>` role and runs under `trusted-ci`'s own OIDC identity. Inputs expose common
build variation (`context`/`dockerfile`/`build-args`/`target`/`platforms`). All caller inputs are validated
and passed via `env:` (never inlined into `run:`) to close the shell-injection class.

**2. App repos become thin callers.** `deploy.yml`/`preview.yml` shrink to ~18/~12 lines: a `build` job that
`uses: build-sign.yml`, a `provenance` job that `uses: slsa-provenance.yml`, and (deploy only) a `deploy` job
that pins the signed digest into `k8s/preprod` and commits. The two reusable workflows are invoked as
**sibling 1-level calls — never nested** — so the OIDC `job_workflow_ref` (→ cosign cert subject) and
`repository` (→ `githubWorkflowRepository`) claims are the well-understood single-level values, not the
2-level-nesting behavior GitHub's docs leave unspecified. **`app-bravo` is the generic starter** teams copy.

**3. Per-team isolation moves to the certificate extension.** Because the shared workflow signs everything,
the cosign cert **subject** is the same for all teams (`…/trusted-ci/build-sign.yml@<sha>`); the per-team gate
is the `githubWorkflowRepository` extension (= the caller app repo, which Fulcio sets from the caller's own
OIDC and another team cannot forge). This is **exactly the pattern `verify-attestations` already uses for
provenance** — the model converges.

**4. Shared-signer policy model with an app-signed escape hatch.** The `policy` module gains
`trusted_ci_build_subject_regexp` + `shared_signer_caller_repos`. For teams in `shared_signer_caller_repos`,
`verify-images` and the `verify-attestations` SBOM block accept the shared `build-sign.yml` identity (gated by
the extension) **as an additional `count:1` alternative alongside** each team's own app-signed identity
(`verify_subjects`). So a team is **shared** (thin caller — the default) **or app-signed** (bespoke, runs its
own build+sign) — the policy is the union of whatever the team is wired for. "Accept both" is therefore a
designed feature, not transition debt; it also makes any future migration zero-gap (old app-signed pods and
new shared-signed pods are both admitted).

**5. `trusted-ci` is public.** Making the shared signer's reusable workflows broadly callable (and unblocking
brand-new repos, which couldn't resolve the private repo's reusable workflows via org-access) is acceptable
because **the signer's integrity comes from app teams being unable to _write_ to `trusted-ci` (CODEOWNERS +
branch protection), not from privacy.** Public read makes the signing workflow auditable.

## Alternatives considered

- **Keep copy-per-app (status quo).** Rejected: doesn't scale; every signing fix touches N repos; high
  copy-paste error surface.
- **Nest `slsa-provenance.yml` inside `build-sign.yml`** (one call from the app). Rejected: makes provenance a
  2-level-nested call, whose OIDC claim behavior GitHub's docs don't specify — and the whole isolation model
  rests on those claims. Sibling 1-level calls keep us on proven behavior.
- **Force every app onto the shared workflow (no app-signed path).** Rejected: bespoke builds exist; a hard
  requirement would block legitimate apps. The escape hatch keeps the common case thin without excluding them.
- **A new less-isolated "shared CI" repo for `build-sign.yml`.** Rejected: the image+SBOM signer must be as
  uncompromisable as the provenance signer, so it belongs in the same app-unwritable trust domain (`trusted-ci`).

## Consequences

### Positive

- New app onboarding drops from ~230 lines of copied CI to ~30 lines of thin callers + the inherent
  Dockerfile/manifests — the shape `app-bravo` and (later) a Backstage scaffolder emit.
- One place to fix/upgrade the signing logic; callers adopt via a SHA bump.
- The whole supply chain (image sig, SBOM, provenance) now signed by app-unwritable identities — strictly
  stronger than app-self-signed image+SBOM.
- Consistent verification shape across image/SBOM/provenance (shared subject + caller extension).

### Negative / cost

- **Concentration of trust:** `build-sign.yml` signs for every shared-path team — a single point of compromise.
  Mitigated by `trusted-ci` write-protection (CODEOWNERS/branch protection), SHA-pinning in callers (a malicious
  push doesn't propagate until a caller bumps), and the workflow holding no secrets (OIDC only). A security fix
  requires bumping the pin in every caller.
- A new public repo cannot resolve a **private** repo's reusable workflows until org-ACL propagation/visibility
  is sorted; we resolved it by making `trusted-ci` public.
- Dual policy paths (shared + app-signed) are slightly more template surface in the `policy` module.

### Not yet (future)

- The per-team `github-actions-ecr-push-<team>` role (`github-oidc` unit) and the policy unit's
  `shared_signer_teams`/`verify_subjects` inputs are still static (`teams.hcl`-derived), **not vended by the
  Crossplane Tenant claim**. A claim-/Backstage-vended tenant would get its ECR repo + Pod-Identity but not its
  CI push identity or verify policies — Phase 3 (vend-from-Backstage) closes this.
