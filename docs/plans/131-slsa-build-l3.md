# SLSA Build L3 — isolated provenance via slsa-github-generator (#131)

> **Status:** **P1–P3 DONE on preprod — Build L3 achieved (2026-05-30).** P0 ruled out the off-the-shelf
> generator for ECR; P1 built the custom isolated signer (`asanexample/trusted-ci`); P2/P3 dropped the
> app's hand-authored provenance so trusted-ci is the **sole** provenance signer and flipped Kyverno
> `verify-attestations` to **Enforce** requiring it. **P4 (replicate to the platform cluster) is the
> remaining step.** Tracking issue: [#131](https://github.com/asanexample/platform/issues/131).
> Design: ADR-042.
>
> **P1 as-built note (differs from the original plan):** AWS does **not** honor the OIDC
> `job_workflow_ref` claim as an IAM trust condition (only `sub`/`aud`), so the planned shared
> `job_workflow_ref`-scoped signer role is infeasible. Instead the signer assumes the caller team's
> existing **`github-actions-ecr-push-<team>`** role (tightest ECR scope, no new IAM, no `github_oidc`
> module change). L3 is unaffected — it comes from the cosign cert identity, verified in P1:
> `Certificate subject = …/trusted-ci/.github/workflows/slsa-provenance.yml@…`, caller extension
> `= asanexample/app-alpha`.

## P0 result (spike, 2026-05-30) — pivot to a custom isolated reusable workflow

**Finding: the off-the-shelf `slsa-framework/slsa-github-generator` container generator cannot be cleanly
fed an ECR credential.** It accepts only a registry username + password (input/secret); it has **no native
AWS OIDC** to mint an ECR token itself. ECR's credential is **necessarily dynamic** (`aws ecr
get-login-password` → a ~12h token), which means:

- it **can't** be a static repo secret passed via `secrets: inherit` / `${{ secrets.* }}` (the canonical
  GHCR pattern), because it expires and rotates per run; and
- it **can't** be forwarded from the build job as a masked job output → **GitHub redacts masked values
  across job boundaries**, and a redacted job-output can't be passed as a reusable-workflow `secrets:`
  value. ([community #25225](https://github.com/orgs/community/discussions/25225),
  [reuse-workflows docs](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows))

The throwaway spike workflow (`app-alpha` `spike/slsa-l3-ecr`, PR #21) `startup_failure`d on every attempt
(actionlint clean locally; interface + canonical caller structure verified; static-secret swap and the
repo Actions-allowlist both ruled out). **The exact startup cause is moot** — even a perfectly-validating
call has no way to hand the generator a *valid* ECR credential, so the runtime would fail on ECR auth
regardless. This is precisely the contingency the P0 gate existed to catch.

**Pivot (decided): build our own isolated reusable workflow** instead of using the off-the-shelf generator.
A reusable workflow living in a **separate, app-team-unwritable repo** (e.g. `asanexample/trusted-ci`)
with **`id-token: write`** can, *inside itself*, run `aws-actions/configure-aws-credentials` →
`aws ecr get-login-password` to mint the ECR token — so **no cross-job credential passing happens at all**
(the wrinkle above disappears), then `cosign attest --type slsaprovenance` keyless with **its own** OIDC
identity. Because app teams cannot edit that repo, the build job cannot influence/forge the provenance →
**still Build L3**. Output stays **legacy cosign `.att`** → **Kyverno unchanged (no `SigstoreBundle`)**; the
only Kyverno change vs the original plan is the attestor identity becomes
`repo:asanexample/trusted-ci/.github/workflows/<name>.yml@…` instead of `…/generator_container_slsa3.yml`.
Everything downstream (P2 dual-accept Audit → P3 generator-only Enforce → P4 platform) is **unchanged**.

## Context

Today app images are **Build L1+**: a SLSA provenance predicate is **hand-authored by a `run:` step in
the build job and signed with that job's own OIDC** (cosign keyless), enforced at admission by
`verify-attestations-team-*` (#115). Because the *build process* both writes and signs its own provenance,
a compromised build step could forge it — that fails L3's "non-falsifiable" bar.

**Key finding (reshapes the effort):** the **slsa-framework/slsa-github-generator** SLSA-3 *container*
reusable workflow:

- is **free** — signs via the **public Sigstore** keyless, **NOT** GitHub Artifact Attestations (so **no
  GitHub Enterprise Cloud**, unlike `actions/attest-build-provenance`);
- stores provenance as a **legacy cosign attestation** (`.att` DSSE), the **same format Kyverno already
  verifies** — so **NO cosign-v3 / `SigstoreBundle` migration, no ECR change** (the dominant cost/risk in
  #131's original framing is **avoided**);
- runs in an **isolated reusable-workflow trust domain** with its **own** OIDC identity the caller's build
  steps cannot influence → that isolation earns **Build L3**.

Kyverno's published SLSA policy confirms the verification shape: standard `keyless` attestor with
`subject: …/generator_container_slsa3.yml@refs/tags/v*`, `predicateType: https://slsa.dev/provenance/v0.2`,
a `builder.id` condition, Rekor — **not** `type: SigstoreBundle`. So we go **straight to L3** (skip an
`attest-build-provenance` L2 detour, which would cost GitHub Enterprise on our private repos).

## Approach

Move **only the provenance** to the isolated generator; keep the image **signature** and **SBOM** as they
are today (app-`<team>` cosign keyless, legacy `.att`) — SLSA *build level* is about provenance. Net: one
new app-CI job + a Kyverno attestor identity swap. No cosign-v3, no SigstoreBundle, no ECR revert (keep
`IMMUTABLE_WITH_EXCLUSION`).

**App CI** (`app-alpha` `deploy.yml` + `preview.yml`): keep build+push+`cosign sign`+SBOM attest; **remove**
the hand-authored provenance step; **add** a separate job
`uses: asanexample/trusted-ci/.github/workflows/slsa-provenance.yml@<pinned-SHA>` passing `image`/`digest`.
That reusable workflow (separate, app-team-unwritable repo) mints its own ECR token via OIDC→AssumeRole and
signs provenance with its **own** identity (L3) — see "P0 result" for why this replaces the off-the-shelf
generator.

**Kyverno** (`policies-chart/templates/verify-attestations.yaml` + units): the SLSA-provenance attestor
identity changes from `app-<team>/deploy.yml` to the **trusted-ci** reusable-workflow identity + a
`builder.id` condition;
**preserve per-team isolation** via a condition that the provenance **source = the team's repo**
(`invocation.configSource.uri ≈ github.com/asanexample/app-<team>`). SBOM attestor + signature policy
unchanged.

## Security model (pressure-tested)

- **What L3 buys:** provenance attribution is **non-forgeable** — an attacker / the registry / a *different*
  repo can't forge provenance *claiming to be* app-`<team>`. It does **not** mean a compromised app-`<team>`
  build can't emit a bad image (that's "trust your own pipeline", out of L3's scope).
- **Per-team isolation does NOT weaken.** The **image-signature policy is unchanged** and still gates
  per-team (`cosign sign` by `app-<team>`). Signature = primary gate; generator provenance = L3 integrity;
  the per-team source-repo condition = defense-in-depth. Keep the signature policy as-is.
- **Third-party-workflow supply chain (#112 lesson):** adding the generator to the *release* pipeline with
  `id-token: write` + ECR creds across the job boundary is real trust surface — **pin to a commit SHA**.
- **L3 holds only after P3** (generator-only + Enforce); the dual-accept window still admits old provenance.
- **Generator version drift:** Dependabot bumps must keep matching the Kyverno `builder.id` regex.
- **Residual:** SBOM stays app-self-attested (doesn't affect the build level); could move it later.

## Phases (each gated; Audit→Enforce, preprod first)

- **P0 — Feasibility spike (gates everything). ✅ DONE 2026-05-30 → off-the-shelf generator rejected for
  ECR; pivot to a custom isolated reusable workflow (see "P0 result" above).**
- **P1 — App provenance via the custom isolated reusable workflow. ✅ DONE + verified (2026-05-30).**
  Created `asanexample/trusted-ci/.github/workflows/slsa-provenance.yml` (private, app-team-unwritable,
  org-only call access, CODEOWNERS=platform): derives the caller team, assumes that team's
  `github-actions-ecr-push-<team>` role (AWS rejects `job_workflow_ref` scoping — see status note),
  mints the ECR token, `cosign attest --type slsaprovenance` keyless. Added the provenance job to
  `app-alpha` `deploy.yml` + `preview.yml` (pinned SHA) alongside the hand-authored step (dual
  provenance). Verified: preview run green, `cosign verify-attestation` shows the **trusted-ci** signer
  - `app-alpha` caller extension.
- **P2 — Kyverno dual-accept, Audit.** Attestor accepts **either** app identity (old) **or** generator
  (new); confirm PolicyReports show the generator path verifies on deploy **and** preview pods; add the
  per-team source condition.
- **P3 — Generator-only + Enforce.** Drop the app-identity entry + the hand-authored step; flip to Enforce.
  Now only isolated-generator provenance is admitted — **L3**.
- **P4 — Platform cluster + docs.** Replicate to platform; document the achieved level + negative test.

## Effort & cost (revised — far smaller than #131's original framing)

- **Effort: ~3–5 days** (P0 landed on the contingency: build the custom isolated reusable workflow +
  trusted-ci repo + ECR-push role, then Kyverno attestor swap + per-team source condition + Audit→Enforce
  on both clusters). SigstoreBundle migration **not** needed. The base ~2–3 days plus the +1–2 day custom
  reusable-workflow build.
- **Cost: ~$0 new infra.** Public Sigstore keyless (free), provenance in ECR (`.att`, KB), no GitHub
  Enterprise, no cosign-v3, no ECR change. Marginal extra Actions minutes for the generator job.

## Verification

1. `cosign verify-attestation --type slsaprovenance --certificate-identity-regexp '…/generator_container_slsa3.yml@refs/tags/v.*' --certificate-oidc-issuer https://token.actions.githubusercontent.com <img>@<digest>` → succeeds; `builder.id` = generator.
2. Kyverno Audit PolicyReport for app-alpha **and** a PR-preview pod: `verify-attestations-team-alpha … "image verified"`.
3. **Negative test (the L3 proof):** app-self-signed provenance no longer satisfies the generator-only
   attestor (rejected under Enforce); provenance whose source is another team's repo fails the source condition.
4. `.kyverno-tests` still 21/21; chart renders; module validates.

## Out of scope / notes

- SBOM stays app-attested. Optionally move to an isolated generator later.
- P3 Enforce flip is a good candidate to land with the from-scratch rebuild, or strictly Audit-first.
- `actions/attest-build-provenance` (GitHub Enterprise) is explicitly **out** — slsa-github-generator gives
  the same L3 for free on private repos.
