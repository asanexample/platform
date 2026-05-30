# Cosign Image Signing — How It All Works

This is the from-scratch explainer. If you've never touched Sigstore/cosign before, start here and
read top to bottom. It explains **why** we sign container images, **what** each moving part does, and
**how** our specific setup (app CI + Kyverno + ECR + IRSA) fits together. Reference material lives in
[ADR-014](../adrs/014-kyverno-as-policy-engine.md), the
[policy catalog](kyverno-policy-catalog.md), and the
[break-glass runbook](../runbooks/kyverno-break-glass.md).

---

## 1. The problem: "is this container image the one we actually built?"

A Kubernetes cluster pulls a container image (e.g. `…/team-alpha/demo@sha256:d60ea84…`) and runs it.
By default the cluster trusts whatever is in the registry. That's a **supply-chain** gap:

- If an attacker pushes a malicious image to your registry (stolen creds, a poisoned CI step, a typo'd
  tag), the cluster will happily run it.
- If one team pushes an image into **another** team's repo path, nothing stops the other team from
  running it.
- You have no cryptographic proof that the image running in prod came from **your** build pipeline and
  not from someone's laptop.

**Image signing** closes this gap. The build pipeline cryptographically **signs** each image it
produces, and the cluster **refuses to run** any image that isn't signed by a build pipeline it trusts.
Think of it as a tamper-evident wax seal: anyone can read what's inside, but only the real sender can
produce the seal, and the recipient checks the seal before opening.

**Cosign** is the tool that creates and checks these seals. It's part of the **Sigstore** project.

---

## 2. The hard part of signing: keys. And how "keyless" avoids them

Traditional signing uses a **private key**: CI holds a secret key, signs with it, and everyone verifies
with the matching public key. That works, but the private key is a liability — you have to store it,
rotate it, keep it out of logs, and if it leaks, an attacker can forge signatures forever. Managing
signing keys safely is genuinely hard.

Sigstore's headline feature is **keyless signing**: **no long-lived private key exists.** Instead it
leans on three pieces working together:

| Piece | What it is | Role in signing |
|-------|-----------|-----------------|
| **OIDC identity** | A short-lived identity token proving "I am GitHub Actions workflow X in repo Y". GitHub hands one to every workflow run. | Proves *who is doing the signing* — without a password or key. |
| **Fulcio** | Sigstore's certificate authority (`https://fulcio.sigstore.dev`). | Takes your OIDC token and issues a **short-lived signing certificate** (~10 min) that embeds your identity. You sign with a one-time key tied to that cert, then throw the key away. |
| **Rekor** | Sigstore's public **transparency log** (`https://rekor.sigstore.dev`). | Records an immutable, append-only entry of *what was signed, by whom, and when*. This is the tamper-evident ledger — even Sigstore can't quietly delete an entry. |

The flow, in plain terms:

1. The CI job asks GitHub for an **OIDC token** ("I'm `repo:asanexample/app-alpha`, workflow
   `deploy.yml`, branch `main`").
2. cosign sends that token to **Fulcio**, which says "verified — here's a 10-minute certificate stamped
   with that exact identity."
3. cosign generates a throwaway key pair, signs the image's **digest** with it, and uploads the
   signature + certificate to **Rekor** (the public log) and stores the signature **next to the image
   in the registry**.
4. The throwaway private key is discarded. There is **nothing to steal or rotate** afterward.

So the trust anchor isn't "a key we protect" — it's **"an identity that GitHub vouches for, certified by
Fulcio, and logged in Rekor."** To verify later, you don't need a public key you saved; you check that
the signature's embedded certificate was issued by Fulcio to **the identity you expect**, and that Rekor
has the record.

> **The single most important idea:** the *identity in the certificate* is what we trust. For us that
> identity is a specific GitHub Actions workflow in a specific repo — e.g.
> `https://github.com/asanexample/app-alpha/.github/workflows/deploy.yml@refs/heads/main`. Only that
> workflow, running in that repo, can produce a signature with that identity. That's the whole security
> model.

---

## 3. The two halves of our system

```text
          ┌─────────────────────────  SIGN (app repo CI)  ─────────────────────────┐
          │                                                                          │
 git push │   build image ──▶ push to ECR ──▶ cosign sign (keyless, by digest)       │
   to main│                       │                    │                             │
          │                       │                    └─▶ OIDC→Fulcio→Rekor          │
          └───────────────────────┼──────────────────────────────────────────────────┘
                                  │  image + its signature now both live in ECR
                                  ▼
          ┌────────────────────  VERIFY (cluster admission)  ────────────────────────┐
          │                                                                            │
  kubectl │   Pod created ──▶ Kyverno verify-images policy ──▶ fetch signature from ECR │
  / ArgoCD│                                    │                        │              │
          │                                    │     check cert identity = expected    │
          │                                    │     workflow + Rekor inclusion        │
          │                          admit ◀───┴───▶ deny (Enforce) / warn (Audit)     │
          └────────────────────────────────────────────────────────────────────────────┘
```

**Half 1 — signing — lives in the *app* repo** (`asanexample/app-alpha`, etc.). The platform doesn't
sign anything; each app's own CI signs its own images.

**Half 2 — verifying — lives in the *platform*** (the `policy` Terragrunt unit → Kyverno on the
cluster). The platform decides which identities to trust and enforces it at admission.

This split is deliberate: an app team can't grant itself trust (that's a platform decision), and the
platform never holds app signing credentials (there are none to hold — keyless).

---

## 4. Half 1 — how the app CI signs (`deploy.yml` / `preview.yml`)

Here is the real signing step from `app-alpha/.github/workflows/deploy.yml`:

```yaml
permissions:
  id-token: write        # ← REQUIRED: lets the job request a GitHub OIDC token (the identity)
  contents: write        # (used later to commit the pinned-digest manifest back)

steps:
  - name: Build and push image
    id: build
    uses: docker/build-push-action@v6
    with:
      push: true
      tags: ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPO }}:${{ github.sha }}

  - name: Install cosign
    uses: sigstore/cosign-installer@v3

  - name: Sign image (cosign keyless)
    run: cosign sign --yes "${ECR_REGISTRY}/${ECR_REPO}@${{ steps.build.outputs.digest }}"
```

Key points, decoded:

- **`id-token: write`** is what makes keyless signing possible — without it the job can't get the OIDC
  token, and `cosign sign` has no identity to present to Fulcio. This is the line people forget.
- **Sign by `@digest`, not by `:tag`.** `steps.build.outputs.digest` is the immutable
  `sha256:…` content hash of the image. Tags can be moved; a digest can't. The signature is bound to the
  exact bytes. (Kyverno later re-checks by digest too.)
- **`cosign sign` with no `--key`** = keyless. cosign auto-detects the GitHub OIDC token, gets a Fulcio
  cert, signs, and logs to Rekor. The resulting signature is stored in ECR as a companion artifact
  (an extra `sha256-….sig` tag sitting next to the image).
- **Sign *before* the manifest is committed.** The workflow signs, *then* updates
  `k8s/preprod/deployment.yaml` to pin the new digest and commits it. So by the time ArgoCD deploys the
  new digest, its signature already exists in ECR — no race where the pod is admitted before the
  signature is published.

`preview.yml` is the same idea for pull requests: it builds/signs on `pull_request`, tagging by
`github.event.pull_request.head.sha`. Its OIDC identity differs from `deploy.yml`'s because the *ref*
is a PR ref (`refs/pull/123/merge`) instead of `refs/heads/main` — which is why the policy matches
previews with a **regex** (see §6).

### What the signature actually proves

Run this against our running image and you can read the identity straight out of it:

```bash
cosign verify \
  829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/demo@sha256:d60ea84… \
  --certificate-identity-regexp 'https://github.com/asanexample/app-alpha/.github/workflows/deploy.yml@refs/heads/main' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

The output's certificate extensions spell out exactly who signed it:

```text
Issuer:  https://token.actions.githubusercontent.com
Subject: https://github.com/asanexample/app-alpha/.github/workflows/deploy.yml@refs/heads/main
githubWorkflowRepository: asanexample/app-alpha
githubWorkflowTrigger:    push
…and "Existence of the claims in the transparency log was verified" (that's the Rekor check)
```

That `Subject` line is the identity Kyverno will insist on.

---

## 5. Half 2 — how the cluster verifies (Kyverno `verify-images`)

On every cluster, Kyverno runs a per-team policy named `verify-images-team-<team>` (rendered from
`infra/modules/policy/policies-chart/templates/verify-images.yaml`). It's an **admission** policy: it
runs when a Pod is *created*, before the Pod is allowed to start.

What it does for a Pod in `team-alpha`:

1. Look at each container image reference. If it matches `…/team-alpha/*`, the policy applies.
2. Fetch that image's **signature** from ECR (this is why Kyverno needs ECR read — see §7).
3. Check the signature's certificate:
   - **Issuer** = `https://token.actions.githubusercontent.com` (it really came from GitHub Actions).
   - **Subject** = the team's expected workflow identity (e.g. app-alpha's `deploy.yml@refs/heads/main`,
     or its `preview.yml` for PRs).
   - **Rekor** inclusion = the signature is recorded in the transparency log.
4. If a valid signature from an accepted identity exists → **admit**. Otherwise → **deny** (Enforce) or
   **warn + record a PolicyReport** (Audit).

The actual policy spec (simplified):

```yaml
verifyImages:
  - imageReferences: ["<team-ecr-prefix>/*"]
    mutateDigest: true        # rewrite tag→digest on admit (see below)
    verifyDigest: true
    required: true            # an image with NO signature is denied, not skipped
    attestors:
      - count: 1              # ANY ONE of the entries below must verify
        entries:
          - keyless:          # stable deploys (main branch)
              issuer: https://token.actions.githubusercontent.com
              subject: "https://github.com/asanexample/app-alpha/.github/workflows/deploy.yml@refs/heads/main"
              rekor: { url: https://rekor.sigstore.dev }
          - keyless:          # PR previews (ref varies per PR → regex)
              issuer: https://token.actions.githubusercontent.com
              subjectRegExp: "https://github.com/asanexample/app-alpha/.github/workflows/preview.yml@refs/.*"
              rekor: { url: https://rekor.sigstore.dev }
```

Three details that matter:

- **`count: 1` + multiple `entries` = "any one of these identities is acceptable."** We normally list two
  (deploy + preview). This is also the hook the org migration used to accept old+new identities at once
  (§8).
- **`required: true`** means an *unsigned* image is rejected, not silently allowed. No signature is as
  bad as a bad signature.
- **`mutateDigest: true`** makes Kyverno rewrite the admitted Pod's image from `:tag` to the verified
  `@sha256:…` digest, so what runs is provably the bytes that were verified. (cosign forbids mutation in
  Audit mode, so we only enable this once the policy is in Enforce.)

---

## 6. Per-team identity: why `team-alpha` can't run `team-bravo`'s image

Each team gets its **own** `verify-images-team-<team>` policy, and each policy only accepts **that
team's** workflow identity. A signature from `app-bravo`'s workflow does **not** satisfy
`verify-images-team-alpha`. So even though all images live in one ECR registry, a team can only run
images its own pipeline signed — the supply-chain analog of the per-team ECR-push and registry-scoping
rules. The team data (which repo signs for which team) is **not** in the module; it comes from
`teams.hcl` at the Terragrunt unit and is passed in as `verify_subjects`.

Where the identities come from (`infra/live/aws/preprod/us-east-1/platform/policy/terragrunt.hcl`):

```hcl
verify_subjects = { for k, v in local.teams : k => [ {
  deploy_subject         = "${repo_url}/.github/workflows/deploy.yml@refs/heads/main"
  preview_subject_regexp = "${repo_url}/.github/workflows/preview.yml@refs/.*"
} ] }
```

`repo_url` is each team's app repo from `teams.hcl`. That's the *only* place the org/repo name appears in
the verify path — which is exactly why an org rename is a coordinated change (§8).

---

## 7. The plumbing: how Kyverno is *allowed* to read signatures from ECR (IRSA)

To verify a signature, Kyverno first has to **download** it from ECR — and ECR is a private AWS
registry. Kyverno authenticates to ECR using **IRSA** (IAM Roles for Service Accounts): its pods assume
an AWS IAM role via the cluster's OIDC provider.

The `policy` module creates this role (`aws_iam_role.kyverno_ecr`) when image verification is enabled:

- **Trust policy:** only the `kyverno-admission-controller` and `kyverno-reports-controller` service
  accounts in the `kyverno` namespace can assume it (scoped by the EKS OIDC `sub`).
- **Permissions (read-only):** `ecr:GetAuthorizationToken` (to log in) plus `BatchGetImage`,
  `GetDownloadUrlForLayer`, `BatchCheckLayerAvailability` — **scoped to `repository/team-*`** only.
  Kyverno can *read* signatures; it cannot push, delete, or touch non-team repos.
- **Cross-account:** images live in the **platform** account's ECR. From **preprod**, Kyverno reads them
  cross-account — allowed by the ECR repo policy's `pull_account_ids`, same path the node role already
  uses to pull images.

So the trust chain for *verification* is: Kyverno pod → IRSA role → ECR (fetch signature) → Fulcio cert
check + Rekor lookup → admit/deny. No signing keys anywhere; everything is identity- and log-based.

---

## 8. Worked example: the org migration "dual-subject" transition (2026-05-29)

This is the clearest real example of why the identity model matters. We moved the repos from the personal
account `gangster` to the org `asanexample`. The problem:

- The **running** image was signed while the repo was still `gangster/app-alpha`, so its signature
  identity is `…github.com/gangster/app-alpha/…deploy.yml@refs/heads/main`.
- After the move, new images sign as `…asanexample/app-alpha/…`.
- If we'd simply switched the policy's expected subject from `gangster` to `asanexample`, the
  **already-running, already-admitted image would fail re-admission** the next time a pod rescheduled —
  an outage.

The fix used `count: 1` + multiple entries to accept **both** identities during the cutover:

1. **Widen** — make `verify_subjects` a *list* per team and include both the `asanexample` identity **and**
   the legacy `gangster` one. `count: 1` means either verifies. Apply. Nothing breaks; both old and new
   signatures are accepted. (Implemented with a `legacy_org = "gangster"` local that derives the old
   subject via `replace(repo_url, "asanexample", "gangster")`.)
2. **Re-sign** — push a commit to `asanexample/app-alpha` main → `deploy.yml` builds a new image and signs
   it under the **asanexample** identity. ArgoCD deploys it; Kyverno admits it via the asanexample entry.
3. **Drop** — once the running image is asanexample-signed, set `legacy_org = ""` and apply. The gangster
   entry disappears; only asanexample is accepted. A reschedule test confirms pods still admit.

That's why the module's `verify_subjects` type is `map(list(object(...)))` rather than a single object —
the list is the seam that makes a zero-downtime identity change possible. Keep the (now-empty)
`legacy_org` scaffold around; it's the template for the next org/identity change.

---

## 9. Audit vs Enforce (rolling it out safely)

`verify-images` has its **own** action knob (`verify_failure_action`), independent of the other policies,
so signature verification can roll out separately:

- **Audit** — a Pod with a missing/wrong signature is **admitted**, but Kyverno records a `PolicyReport`
  flagging it. Use this first to confirm every legit workload already signs correctly, with zero risk of
  blocking deploys. (`mutateDigest` is off in Audit — cosign forbids mutation there.)
- **Enforce** — a Pod with a missing/wrong signature is **denied at admission**. This is the real gate.
  Preprod and platform run verify in **Enforce** today.

The matching webhook `failurePolicy` follows: `Ignore` (fail-open) under Audit, `Fail` (fail-closed)
under Enforce. `background: false` because verification needs the live admission request, not a
background re-scan.

---

## 10. Operating it

### Verify an image by hand

```bash
# log Docker/cosign into ECR first
aws ecr get-login-password --region us-east-1 --profile platform \
  | cosign login 829808296602.dkr.ecr.us-east-1.amazonaws.com --username AWS --password-stdin

cosign verify \
  829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/demo@sha256:<digest> \
  --certificate-identity-regexp 'https://github.com/asanexample/app-<team>/.github/workflows/(deploy|preview).yml@.*' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

A clean exit (and a printed `Subject:`) = good signature. A non-zero exit = no/invalid signature for that
identity.

### When a Pod is denied at admission

The deny message names the policy. Walk it back:

1. **Is the image signed at all?** Run the `cosign verify` above. If it fails, the app's CI didn't sign
   (check the `Sign image` step ran, and that `id-token: write` is set).
2. **Right identity?** The `Subject` in the signature must match the team's `verify_subjects` (correct
   org, repo, workflow file, ref). After a repo move/rename, this is the usual culprit — see §8.
3. **Can Kyverno reach ECR?** If signatures exist but admission still fails with fetch errors, check the
   IRSA role (§7) is attached to the Kyverno controllers (`kubectl -n kyverno get sa
   kyverno-admission-controller -o yaml` should show the `eks.amazonaws.com/role-arn` annotation) and
   that the pods were restarted to pick it up.
4. **Audit to unblock, then fix forward.** If a legitimate workload is blocked and you need air, flip
   `verify_failure_action = "Audit"` for that env, apply, fix the signing, then return to Enforce. Don't
   weaken the *identity* to fit a bad image. For genuine exceptions, follow the
   [break-glass runbook](../runbooks/kyverno-break-glass.md).

### What an app team must do (the short version)

To pass verification, an app's CI must, on the build that produces the deployed image:
`id-token: write` permission → build & push by digest → `cosign sign --yes …@<digest>` keyless. Nothing
else; no keys, no secrets. The platform side (trusting that identity) is wired from `teams.hcl`.

---

## 10b. Isolated build provenance (SLSA Build L3 — ADR-042)

The image **signature** above proves *who built* an image. The **SLSA provenance** attestation proves
*how* it was built. Today the provenance is hand-authored and signed by the app's own build job — so a
compromised build could forge it (Build L1+). [ADR-042](../adrs/042-isolated-build-provenance-slsa-l3.md)
moves provenance signing to an **isolated reusable workflow** the app team cannot edit:

- The signer lives in `asanexample/trusted-ci` (private, org-only call access, CODEOWNERS=platform). App
  CI calls it as a job (`uses: …/trusted-ci/.github/workflows/slsa-provenance.yml@<sha>`, pinned).
- Because it is a **reusable** workflow, the Fulcio cert's **subject is the signer workflow, not the
  caller** — so the app build can't forge provenance attributed to trusted-ci. That isolation is the
  SLSA **Build L3** lever. The cert's `GitHub Workflow Repository` extension still records the caller
  (`app-<team>`), which per-team verification keys on.
- It mints its own ECR token by assuming the **caller team's `github-actions-ecr-push-<team>` role**
  (AWS doesn't honor the `job_workflow_ref` claim in trust policies — only `sub`/`aud`), then
  `cosign attest --type slsaprovenance` (legacy `.att`, same format this doc's verification uses).

Verify the isolated provenance by hand:

```bash
cosign verify-attestation --type slsaprovenance \
  --certificate-identity-regexp 'https://github.com/asanexample/trusted-ci/.github/workflows/slsa-provenance.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-github-workflow-repository asanexample/app-<team> \
  <registry>/team-<team>/<app>@<digest>
```

Rollout is dual-provenance first (both the old hand-authored and the new isolated attestation exist), so
admission never breaks; Kyverno swaps the SLSA attestor to the trusted-ci identity in a later phase. The
image **signature** policy (sections 4–6) is unchanged and remains the primary per-team gate.

---

## 11. Glossary

| Term | Meaning |
|------|---------|
| **Cosign** | The CLI that signs/verifies container images. Part of Sigstore. |
| **Sigstore** | The umbrella project: cosign + Fulcio + Rekor. |
| **Keyless signing** | Signing with a short-lived Fulcio cert tied to an OIDC identity, with no long-lived private key to manage. |
| **OIDC token** | Short-lived proof of identity GitHub issues to a workflow run (needs `id-token: write`). |
| **Fulcio** | Sigstore CA; exchanges an OIDC token for a ~10-min signing certificate stamped with the identity. |
| **Rekor** | Sigstore's public, append-only transparency log of signatures. The tamper-evident ledger. |
| **Certificate identity / Subject** | The workflow identity baked into the signing cert, e.g. `…/asanexample/app-alpha/.github/workflows/deploy.yml@refs/heads/main`. **This is what we trust.** |
| **Digest** | The immutable `sha256:…` content hash of an image. Signatures bind to it. |
| **Attestor / `count`** | The set of acceptable signing identities for a policy rule; `count: 1` = any one suffices. |
| **`mutateDigest`** | Kyverno rewriting an admitted Pod's image tag to the verified digest. |
| **IRSA** | IAM Roles for Service Accounts — how Kyverno pods assume an AWS role (here, to read ECR signatures). |
| **Audit / Enforce** | Verification records-but-admits (Audit) vs denies (Enforce) on failure. |

---

## See also

- [ADR-014 — Kyverno as policy engine](../adrs/014-kyverno-as-policy-engine.md) (the broader decision +
  phased rollout; image verification is Phase 3)
- [Kyverno policy catalog](kyverno-policy-catalog.md) (every policy, per cluster)
- [Kyverno break-glass runbook](../runbooks/kyverno-break-glass.md) (legitimate exceptions)
- `CLAUDE.md` → "Authoring Policy-Compliant Workloads" (the app-author checklist, incl. "images must be
  cosign-signed")
