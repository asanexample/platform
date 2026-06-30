# ADR-042: Isolated Build Provenance for SLSA Build L3

**Date:** 2026-05-30

**Status:** Accepted — extends [ADR-036](036-github-actions-oidc-federation.md) (GitHub Actions OIDC
federation) and builds on the image-signing/attestation chain (platform #108). **P1–P3 done on preprod
(2026-05-30): app-alpha emits trusted-ci as its SOLE provenance signer and preprod Kyverno
verify-attestations is in Enforce requiring it — Build L3 achieved on preprod.** P4 (platform-cluster
replication) pending. **Generalized by [ADR-050](050-shared-build-sign-reusable-workflow.md)**, which moved
**image + SBOM** signing into a sibling shared reusable workflow (`trusted-ci/build-sign.yml`) using the same
isolated trust domain and `githubWorkflowRepository`-extension gating this ADR established for provenance.

## Context

App images already carry a SLSA provenance attestation, but it is **hand-authored by a `run:` step in
the app's own build job and signed with that job's own keyless OIDC identity** (`app-alpha`
`deploy.yml`/`preview.yml`), then enforced at admission by Kyverno (`verify-attestations-team-*`, #115).
Because the *build process both writes and signs its own provenance*, a compromised build step could
forge it — which fails [SLSA](https://slsa.dev) **Build L3**'s "provenance is non-falsifiable by the
build" bar. We are at roughly Build L1+ today.

The goal: produce provenance whose signer the calling build **cannot influence**, so an attacker (or a
different repo, or the registry) cannot forge provenance *claiming to be* `app-<team>`.

### Alternatives considered

**1. `slsa-framework/slsa-github-generator` container generator (rejected — P0 spike, #131).** Runs in
its own reusable-workflow trust domain (free, public Sigstore, legacy `.att`). But it **cannot be cleanly
fed an ECR credential**: ECR's token is dynamic, can't be a static secret, and a masked job-output can't
be forwarded as a reusable-workflow secret; the generator has **no native AWS OIDC** to mint the token
itself.

**2. GitHub Artifact Attestations (`actions/attest-build-provenance`) (rejected).** Same L3 for free only
on *public* repos; on **private** repos it needs **GitHub Enterprise Cloud**. Our app repos are private.

**3. A custom isolated reusable workflow we own (chosen).** A reusable workflow in a separate,
app-team-unwritable repo, with its own OIDC identity, that mints its own ECR token and cosign-signs the
provenance.

## Decision

Move **only the provenance** to an isolated signer; keep the per-team image **signature** and **SBOM** as
they are (app-`<team>` keyless). SLSA *build level* is about provenance.

### The isolated signer — `asanexample/trusted-ci`

A dedicated repo holds `.github/workflows/slsa-provenance.yml` (`on: workflow_call`, inputs `image` +
`digest`). It assumes an AWS role, runs `aws ecr get-login-password` via `amazon-ecr-login`, installs
cosign (pinned v2.5.2, legacy `.att`), builds the SLSA v0.2 predicate, and runs `cosign attest --type
slsaprovenance` keyless.

**Why this is L3 (the load-bearing fact, verified):** for a **reusable** workflow, the Fulcio
certificate's signer identity (SAN) is the *reusable workflow* — verified in P1:

```text
Certificate subject: https://github.com/asanexample/trusted-ci/.github/workflows/slsa-provenance.yml@<sha>
GitHub Workflow Repository: asanexample/app-alpha
```

— **not the caller** ([cosign #2936](https://github.com/sigstore/cosign/discussions/2936)). App teams
have **no write access** to `trusted-ci`, so they cannot alter the signing workflow → the provenance
signer is outside the build's control. The **L3 guarantee comes from this cosign certificate identity,
not from any AWS role.** The certificate's `GitHub Workflow Repository` extension records the *caller*
(`app-<team>`) — the cryptographically-bound key P2 uses for per-team verification.

### AWS trust — assume the caller team's existing push role

The signer needs an ECR credential to push the `.att`. The ideal scoping would be "assumable only while
the trusted-ci workflow runs" via the OIDC **`job_workflow_ref`** claim — but **AWS does not honor
`job_workflow_ref` as an IAM trust condition.** AWS reliably exposes **only `sub` and `aud`** as STS
condition keys for the GitHub OIDC provider; a `StringLike` on the unpopulated `job_workflow_ref` key
never matches, so a `job_workflow_ref`-scoped role returns `AccessDenied` even though the token contains
the claim. (Verified empirically: decoded token claim matched the trust policy exactly, yet STS denied;
[aws-actions/configure-aws-credentials#912](https://github.com/aws-actions/configure-aws-credentials/issues/912).)

So the signer **assumes the caller team's existing `github-actions-ecr-push-<team>` role** (ADR-036),
derived from the caller repo (`asanexample/app-<team>`). That role's trust already matches the caller's
`sub` (the token's `sub` is the *calling* app repo), and its ECR scope is already restricted to
`team-<team>/*` — the tightest possible scope, and **no new IAM role**. This is safe because the AWS role
is **only ECR-push transport**; the non-forgeability guarantee is the cosign certificate identity, which
the app build cannot produce regardless of which role pushes the bytes.

### Containment

1. **GitHub layer:** `trusted-ci` is **private** with reusable-workflow call access limited to the
   organization → arbitrary external/public repos can't call it.
   ([richardfan, 2024](https://blog.richardfan.xyz/2024/08/02/reusable-workflow-is-good-until-you-realize-your-identity-is-also-reusable-by-anyone.html))
2. **In-workflow guard:** the workflow derives the team from the caller and refuses to attest an image
   outside that team's `team-<team>/*` namespace.
3. **Per-team ECR role:** the assumed role can only push to the caller team's repos.
4. **Verification layer (P2):** Kyverno will verify **both** the trusted-ci signer identity **and** the
   certificate's **GitHub-workflow-repository extension** = the team's own `app-<team>` repo
   (`--certificate-github-workflow-repository`).

### Rollout (each gated, preprod first)

- **P1 (done):** trusted-ci repo + reusable signer; provenance job in app CI **alongside** the
  hand-authored step (**dual provenance**); no Kyverno change → zero admission risk. Verified end-to-end.
- **P2 (done):** Kyverno dual-accept (app *or* trusted-ci identity) + the per-team caller-extension
  condition (`attest_caller_repos`).
- **P3 (done, 2026-05-30):** generator-only + Enforce on preprod; dropped the hand-authored step
  (app-alpha `deploy.yml` now signs the SOLE provenance via trusted-ci) → **Build L3 achieved on
  preprod**. Preprod `verify-attestations` re-flipped to Enforce.
- **P4 (pending):** replicate to the platform cluster + negative test. The platform `policy` unit does
  not yet carry `attest_caller_repos`/trusted-ci verification; tenants run on preprod today, so this is
  lower priority.

## Consequences

### Positive

- **Provenance becomes non-forgeable by the build** — the L3 lever, verified in P1.
- **No new infra cost and no new IAM** — public Sigstore keyless, provenance in ECR (`.att`), and the
  signer reuses each team's existing push role. No GitHub Enterprise, no cosign v3, no ECR change.
- **No Kyverno format change** — legacy `.att`; the only P2/P3 change is the attestor identity.
- **Tightest ECR scope** — per-team push role, so the signer can only ever touch the caller team's repos.

### Negative

- **`job_workflow_ref` is not usable in AWS trust policies** — the clean "shared signer, scoped to the
  workflow" design is not available. We fall back to per-team `sub`-scoped roles (this ADR). Revisit if
  AWS adds reliable `job_workflow_ref` support.
- **Signer shares the app's push role** — CloudTrail can't distinguish image-push from attestation-push
  by IAM role (only by the cosign certificate inside the attestation). Acceptable: the role is only
  transport.
- **New supply-chain surface** — the signer in the release path with `id-token: write` + ECR push.
  Mitigated by pinning the app's `uses:` to a commit SHA, the in-workflow team guard, and Dependabot on
  the signer's actions. SHA-pinning the signer's own third-party actions is a follow-up.
- **L3 holds on preprod as of P3** — during the earlier P2 dual-accept window the old forgeable
  provenance was still admitted; that window is closed on preprod now that the hand-authored step is
  dropped and Enforce requires the trusted-ci signer. The platform cluster (P4) is not yet at L3.
- **Branch protection unavailable on the private `trusted-ci`** under the org's current plan; isolation
  rests on app teams not being write-collaborators (+ CODEOWNERS). Enable it on a paid plan.
- **What L3 does NOT buy** — it does not stop a compromised `app-<team>` build from emitting a bad image
  (that's "trust your own pipeline", out of scope). The signature still gates *which* identity built it.
