# Cosign Image Signing — How It All Works

This is the from-scratch explainer. If you've never touched Sigstore/cosign before, start here and
read top to bottom. It explains **why** we sign container images, **what** each moving part does, and
**how** our specific setup (a shared signing workflow called by app CI + Kyverno + ECR + IRSA) fits
together. Reference material lives in
[ADR-014](../adrs/014-kyverno-as-policy-engine.md),
[ADR-050](../adrs/050-shared-build-sign-reusable-workflow.md) (the shared `build-sign.yml`), the
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
> identity is a specific GitHub Actions workflow — the **shared** signing workflow
> `https://github.com/asanexample/trusted-ci/.github/workflows/build-sign.yml@<sha>` — paired with the
> certificate's `githubWorkflowRepository` extension naming the **caller** app repo (e.g.
> `asanexample/app-alpha`). Fulcio sets that extension from the caller's *own* OIDC, so another team can't
> forge it. The workflow path is the same for everyone; the per-team gate is which caller repo invoked it.
> That's the whole security model. (See [ADR-050](../adrs/050-shared-build-sign-reusable-workflow.md) for
> why image+SBOM signing moved to a shared, app-team-unwritable workflow — the same isolation pattern
> provenance already used.)

---

## 3. The two halves of our system

```text
          ┌───────────────  SIGN (shared trusted-ci/build-sign.yml, called by app CI)  ───────────────┐
          │                                                                                            │
 git push │   build image ──▶ push to ECR ──▶ cosign sign image + SBOM (keyless, by digest)            │
   to main│                       │                    │                                               │
          │                       │                    └─▶ OIDC→Fulcio→Rekor                            │
          └───────────────────────┼────────────────────────────────────────────────────────────────────┘
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

**Half 1 — signing — is *triggered* by the app repo but *runs* in the shared, app-team-unwritable
workflow** `asanexample/trusted-ci/.github/workflows/build-sign.yml`. Each app repo's `deploy.yml` /
`preview.yml` is a **thin caller** that invokes `build-sign.yml` (image + SBOM signing) and
`slsa-provenance.yml` (provenance, §10b) as sibling jobs, then pins the signed digest. The signing
itself happens under trusted-ci's own OIDC identity — an app team can't edit the signer (CODEOWNERS /
branch protection on trusted-ci), so a compromised app build can't change *how* it signs. See
[ADR-050](../adrs/050-shared-build-sign-reusable-workflow.md).

**Half 2 — verifying — lives in the *platform*** (the `policy` Terragrunt unit → Kyverno on the
cluster). The platform decides which identities to trust and enforces it at admission.

This split is deliberate: an app team can't grant itself trust (that's a platform decision), can't alter
the shared signer, and the platform never holds app signing credentials (there are none to hold —
keyless).

---

## 4. Half 1 — how images get signed (the shared `build-sign.yml`, called by the app)

The app repo no longer signs the image itself. Its `deploy.yml` / `preview.yml` are **thin callers**:
sibling 1-level jobs that invoke the shared signer and the provenance signer, plus a `deploy` job that
pins the resulting signed digest. The generic reference implementation is **`app-bravo`** (previously
`app-alpha` carried inline build/sign — that's the legacy shape, still supported as a fallback, §8).

Here is the real caller shape from `app-bravo/.github/workflows/deploy.yml`:

```yaml
permissions:
  id-token: write        # ← REQUIRED: the *caller's* OIDC identity is what stamps the cert's
                         #   githubWorkflowRepository extension (= asanexample/app-bravo)
  contents: write        # (used later to commit the pinned-digest manifest back)

jobs:
  build-sign:            # image + SBOM, signed under trusted-ci's OWN identity (not the app's)
    uses: asanexample/trusted-ci/.github/workflows/build-sign.yml@<sha>   # pinned
    secrets: inherit

  provenance:            # SLSA Build L3 provenance — same isolation, see §10b (ADR-042)
    uses: asanexample/trusted-ci/.github/workflows/slsa-provenance.yml@<sha>
    needs: build-sign
    secrets: inherit

  deploy:                # pin the signed @digest into k8s/, commit, let ArgoCD roll it out
    needs: [build-sign, provenance]
    runs-on: ubuntu-latest
    steps:
      - run: # update k8s/preprod/deployment.yaml to the verified digest, then commit
```

Key points, decoded:

- **The signing runs in `trusted-ci`, not the app.** `build-sign.yml` builds, pushes by digest, then
  `cosign sign`s **both the image and its SBOM attestation** keyless — under **trusted-ci's** OIDC
  identity. Because it's a **reusable** workflow, the Fulcio cert's *subject* is the **signer**
  (`…/trusted-ci/.github/workflows/build-sign.yml@<sha>`), the **same for every team**. App teams can't
  edit `build-sign.yml` (CODEOWNERS / branch protection), so they can't change *how* signing happens.
  This is exactly the isolation provenance already used (§10b); ADR-050 extends it to image + SBOM.
- **`id-token: write` on the caller** still matters — but now it stamps the cert's
  **`githubWorkflowRepository`** extension with the **caller** repo (`asanexample/app-bravo`). Fulcio
  sets that from the caller's own OIDC, so one team can't forge another's caller value. **That extension
  is the per-team gate** (§6), replacing the old per-team *subject*.
- **Sign by `@digest`, not by `:tag`.** The build output is the immutable `sha256:…` content hash of
  the image. Tags can be moved; a digest can't. The signature is bound to the exact bytes. (Kyverno
  later re-checks by digest too.)
- **Keyless** = no `--key`. cosign auto-detects the OIDC token, gets a Fulcio cert, signs, and logs to
  Rekor. The resulting signature is stored in ECR as a companion artifact (an extra `sha256-….sig` tag
  next to the image).
- **Sign *before* the manifest is committed.** `build-sign.yml` signs, *then* the caller's `deploy` job
  pins the new digest in `k8s/preprod/deployment.yaml` and commits it. So by the time ArgoCD deploys the
  new digest, its signature already exists in ECR — no race where the pod is admitted before the
  signature is published.

`preview.yml` is the same idea for pull requests: it calls the same `build-sign.yml`, tagging by
`github.event.pull_request.head.sha`. Because the signer is shared, the cert **subject is identical** to
deploy's; the caller-repo extension is likewise identical (`asanexample/app-bravo`) — what differs is the
caller's *trigger* (`pull_request`), not the trust identity. (Under the legacy app-signed fallback, a
preview's identity differed from deploy's because its *ref* was a PR ref — which is why the policy still
also matches the legacy app subjects with a **regex**, see §6.)

### What the signature actually proves

Run this against our running image and you can read the identity straight out of it:

```bash
cosign verify \
  829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/demo@sha256:d60ea84… \
  --certificate-identity-regexp '^https://github\.com/asanexample/trusted-ci/\.github/workflows/build-sign\.yml@' \
  --certificate-github-workflow-repository asanexample/app-alpha \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

The output's certificate extensions spell out exactly who signed it — note the **subject is the shared
signer** while the **repository extension is the caller team**:

```text
Issuer:  https://token.actions.githubusercontent.com
Subject: https://github.com/asanexample/trusted-ci/.github/workflows/build-sign.yml@<sha>
githubWorkflowRepository: asanexample/app-alpha
githubWorkflowTrigger:    push
…and "Existence of the claims in the transparency log was verified" (that's the Rekor check)
```

The `Subject` is the **same for every team** (the shared signer); it's the `githubWorkflowRepository`
extension — `asanexample/app-alpha` — that Kyverno keys on per team. (An image signed under the legacy
app-signed `deploy.yml`/`preview.yml` subject is still accepted as a fallback, §8.)

---

## 5. Half 2 — how the cluster verifies (Kyverno `verify-images`)

On every cluster, Kyverno runs a per-team policy named `verify-images-team-<team>` (rendered from
`infra/modules/policy/policies-chart/templates/verify-images.yaml`). It's an **admission** policy: it
runs when a Pod is *created*, before the Pod is allowed to start.

What it does for a Pod in `team-alpha`:

1. Look at each container image reference. If it matches `…/team-alpha/*`, the policy applies.
2. Fetch that image's **signature** from ECR (this is why Kyverno needs ECR read — see §7).
3. Check the signature's certificate. Either of two identities is acceptable (`count: 1`):
   - **Shared signer (primary):** **Subject** matches the shared
     `…/trusted-ci/.github/workflows/build-sign.yml@…` **and** the
     **`githubWorkflowRepository`** extension equals the team's app repo (e.g. `asanexample/app-alpha`).
   - **App-signed (fallback):** **Subject** = the team's own `deploy.yml@refs/heads/main` (or
     `preview.yml` for PRs) — retained as the escape hatch for bespoke-build apps (§8).
   - In both cases: **Issuer** = `https://token.actions.githubusercontent.com` and **Rekor** inclusion
     (the signature is recorded in the transparency log).
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
          - keyless:          # PRIMARY: shared trusted-ci signer, gated per-team by the caller-repo extension
              issuer: https://token.actions.githubusercontent.com
              subjectRegExp: "^https://github.com/asanexample/trusted-ci/.github/workflows/build-sign.yml@"
              additionalExtensions:
                githubWorkflowRepository: "asanexample/app-alpha"   # the CALLER repo = the per-team gate
              rekor: { url: https://rekor.sigstore.dev }
          - keyless:          # FALLBACK: legacy app-signed stable deploys (main branch)
              issuer: https://token.actions.githubusercontent.com
              subject: "https://github.com/asanexample/app-alpha/.github/workflows/deploy.yml@refs/heads/main"
              rekor: { url: https://rekor.sigstore.dev }
          - keyless:          # FALLBACK: legacy app-signed PR previews (ref varies per PR → regex)
              issuer: https://token.actions.githubusercontent.com
              subjectRegExp: "https://github.com/asanexample/app-alpha/.github/workflows/preview.yml@refs/.*"
              rekor: { url: https://rekor.sigstore.dev }
```

The primary entry comes from the module's new `trusted_ci_build_subject_regexp` + the per-team caller
from `shared_signer_caller_repos`; the two app-signed entries come from `verify_subjects` (retained as
the bespoke-build fallback — the "heterogeneity model").

Three details that matter:

- **`count: 1` + multiple `entries` = "any one of these identities is acceptable."** The shared-signer
  entry is the primary; the app-signed deploy + preview entries are kept as a fallback. This is also the
  hook the org migration used to accept old+new identities at once (§8).
- **`required: true`** means an *unsigned* image is rejected, not silently allowed. No signature is as
  bad as a bad signature.
- **`mutateDigest: true`** makes Kyverno rewrite the admitted Pod's image from `:tag` to the verified
  `@sha256:…` digest, so what runs is provably the bytes that were verified. (cosign forbids mutation in
  Audit mode, so we only enable this once the policy is in Enforce.)

---

## 6. Per-team identity: why `team-alpha` can't run `team-bravo`'s image

Each team gets its **own** `verify-images-team-<team>` policy, and each policy only accepts **that
team's** identity. The signer workflow (`build-sign.yml`) is now **shared**, so the per-team gate is the
certificate's **`githubWorkflowRepository` extension** — the **caller** app repo. Fulcio stamps that
from the caller's *own* OIDC token, so `app-bravo` cannot produce a signature whose extension reads
`asanexample/app-alpha`; `verify-images-team-alpha` requires exactly that value. (The retained
app-signed fallback gates the old way, on the per-team *subject*.) So even though all images live in one
ECR registry and share one signer, a team can only run images its own pipeline triggered — the
supply-chain analog of the per-team ECR-push and registry-scoping rules. This is the **same** mechanism
provenance verification already used (§10b). The team data (which caller repo maps to which team) is
**not** in the module; it comes from `teams.hcl` at the Terragrunt unit and is passed in via
`shared_signer_caller_repos` (the shared-signer gate) and `verify_subjects` (the app-signed fallback).

> **These policies stay platform-owned — for *every* team.** `verify-images` (and `verify-attestations`,
> §10b) live in the `policy` Terragrunt unit for **all** teams, including those migrated to a Crossplane
> `XTenant` claim. They are **deliberately not** part of the Environment claim/Composition: an environment must not
> own its own signature **trust root** (it could then trust its own forged identity). So while the claim
> owns a migrated team's *guardrail* policies (`restrict-*`), the signature/attestation **trust** policies
> remain platform-owned. `teams.hcl` still supplies the per-team repo→identity mapping
> (`shared_signer_caller_repos` for the shared-signer gate, plus `verify_subjects` for the app-signed
> fallback) for the `policy` unit — that mapping is read for migrated teams too. See
> [Crossplane Environment API](crossplane-environment-api.md) ("supply-chain split") and ADR-014/046.

Where the identities come from (`infra/live/aws/preprod/us-east-1/platform/policy/terragrunt.hcl`):

```hcl
# Shared signer (primary): one regexp for everyone, gated per-team by the caller repo.
trusted_ci_build_subject_regexp = "^https://github.com/asanexample/trusted-ci/.github/workflows/build-sign.yml@"
shared_signer_caller_repos      = { for k, v in local.teams : k => v.repo }   # e.g. asanexample/app-alpha

# App-signed (fallback): the team's own deploy/preview subjects.
verify_subjects = { for k, v in local.teams : k => [ {
  deploy_subject         = "${repo_url}/.github/workflows/deploy.yml@refs/heads/main"
  preview_subject_regexp = "${repo_url}/.github/workflows/preview.yml@refs/.*"
} ] }
```

`repo_url` is each team's app repo from `teams.hcl`. With the shared signer, the per-team org/repo name
now appears as the **caller** in `shared_signer_caller_repos` (and still in the app-signed
`verify_subjects` fallback) — which is why an org rename is a coordinated change (§8).

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

The same `count: 1` widen→re-sign→drop pattern is how the **shared-signer** cutover (ADR-050) shipped
without an outage: the policy accepted the legacy app-signed subject **and** the new shared
`build-sign.yml` identity at once, apps re-signed via the shared workflow, and the app-signed entry was
*retained* (not dropped) as the bespoke-build fallback. Alpha and bravo migrated; preprod is in Enforce
on the shared signer as of 2026-06-03.

---

## 9. Audit vs Enforce (rolling it out safely)

`verify-images` has its **own** action knob (`verify_failure_action`), independent of the other policies,
so signature verification can roll out separately:

- **Audit** — a Pod with a missing/wrong signature is **admitted**, but Kyverno records a `PolicyReport`
  flagging it. Use this first to confirm every legit workload already signs correctly, with zero risk of
  blocking deploys. (`mutateDigest` is off in Audit — cosign forbids mutation there.)
- **Enforce** — a Pod with a missing/wrong signature is **denied at admission**. This is the real gate.
  Preprod and platform run verify in **Enforce** today; preprod is live on the shared `build-sign.yml`
  signer in Enforce as of 2026-06-03 (alpha + bravo migrated, ADR-050).

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
  --certificate-identity-regexp '^https://github\.com/asanexample/trusted-ci/\.github/workflows/build-sign\.yml@' \
  --certificate-github-workflow-repository asanexample/app-<team> \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

A clean exit (and a printed `Subject:`) = good signature. A non-zero exit = no/invalid signature for that
identity. (For an image still on the legacy app-signed fallback, swap the identity regexp for
`'https://github.com/asanexample/app-<team>/.github/workflows/(deploy|preview).yml@.*'` and drop the
`--certificate-github-workflow-repository` flag.)

### When a Pod is denied at admission

The deny message names the policy. Walk it back:

1. **Is the image signed at all?** Run the `cosign verify` above. If it fails, the app's CI didn't sign
   (check the `build-sign` job actually ran — the caller invoked
   `asanexample/trusted-ci/.github/workflows/build-sign.yml` — and that the caller set `id-token: write`).
2. **Right identity?** The signature's `Subject` must be the shared `build-sign.yml` signer **and** its
   `githubWorkflowRepository` extension must equal the team's caller repo (`shared_signer_caller_repos`);
   or, for the fallback, the `Subject` must match the team's app-signed `verify_subjects`. After a repo
   move/rename, the caller-repo mismatch is the usual culprit — see §8.
3. **Can Kyverno reach ECR?** If signatures exist but admission still fails with fetch errors, check the
   IRSA role (§7) is attached to the Kyverno controllers (`kubectl -n kyverno get sa
   kyverno-admission-controller -o yaml` should show the `eks.amazonaws.com/role-arn` annotation) and
   that the pods were restarted to pick it up.
4. **Audit to unblock, then fix forward.** If a legitimate workload is blocked and you need air, flip
   `verify_failure_action = "Audit"` for that env, apply, fix the signing, then return to Enforce. Don't
   weaken the *identity* to fit a bad image. For genuine exceptions, follow the
   [break-glass runbook](../runbooks/kyverno-break-glass.md).

### What an app team must do (the short version)

To pass verification, an app's `deploy.yml`/`preview.yml` must be a **thin caller** of the shared signer:
set `id-token: write`, then `uses: asanexample/trusted-ci/.github/workflows/build-sign.yml@<sha>` (image +
SBOM signing) and `slsa-provenance.yml` (provenance), and pin the resulting `@digest`. The shared workflow
does the build/push/sign; the app holds no keys or secrets. `app-bravo` is the reference implementation,
and the platform side (trusting that identity) is wired from `teams.hcl`. (A bespoke-build app may still
self-sign under the app-signed fallback — §8 — but the shared caller is the default.)

---

## 10b. Isolated build provenance (SLSA Build L3 — ADR-042)

The image **signature** above proves *who built* an image. The **SLSA provenance** attestation proves
*how* it was built. The app's **sole** provenance is now signed by an **isolated reusable workflow** the
app team cannot edit — the SLSA **Build L3** cutover ([ADR-042](../adrs/042-isolated-build-provenance-slsa-l3.md)),
completed on **preprod** (2026-05-30). Previously the provenance was hand-authored and signed by the
app's own build job, which a compromised build could forge (Build L1+):

- The signer lives in `asanexample/trusted-ci` (now a **public** repo — its integrity comes from app
  teams being unable to **write** to it, CODEOWNERS=platform + branch protection, not from privacy). App
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

The rollout was dual-provenance first (old hand-authored + new isolated attestation both present) so
admission never broke; **preprod has since dropped the hand-authored step**, and Kyverno's
`verify-attestations` is in **Enforce** requiring the trusted-ci identity — **Build L3 on preprod**.
Replicating to the **platform** cluster is the remaining step (ADR-042 P4). The image **signature**
policy (sections 4–6) remains the primary per-team gate.

> **SBOM attestations follow the same shared-signer model (ADR-050).** The image's **SBOM** attestation
> is signed by the same shared `build-sign.yml` (not the provenance workflow, not the app), so
> `verify-attestations`' SBOM block was widened to accept the shared `build-sign.yml` identity
> (`subjectRegExp` + the `githubWorkflowRepository` caller extension) as an additional `count: 1`
> alternative **alongside** the team's existing app-signed identity (`verify_subjects`) — the same
> primary-plus-fallback shape as §5. Provenance verification (above) is unchanged: it always keyed on the
> caller-repo extension, which is precisely the pattern image+SBOM signing now adopt.

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
| **Certificate identity / Subject** | The **signer** workflow baked into the signing cert. Primary: the shared `…/asanexample/trusted-ci/.github/workflows/build-sign.yml@<sha>` (same for every team); app-signed fallback: `…/asanexample/app-alpha/.github/workflows/deploy.yml@refs/heads/main`. |
| **`githubWorkflowRepository`** | Cert extension naming the **caller** repo (e.g. `asanexample/app-alpha`), set by Fulcio from the caller's own OIDC. With the shared signer this is the **per-team gate** — unforgeable across teams. |
| **Digest** | The immutable `sha256:…` content hash of an image. Signatures bind to it. |
| **Attestor / `count`** | The set of acceptable signing identities for a policy rule; `count: 1` = any one suffices. |
| **`mutateDigest`** | Kyverno rewriting an admitted Pod's image tag to the verified digest. |
| **IRSA** | IAM Roles for Service Accounts — how Kyverno pods assume an AWS role (here, to read ECR signatures). |
| **Audit / Enforce** | Verification records-but-admits (Audit) vs denies (Enforce) on failure. |

---

## See also

- [ADR-014 — Kyverno as policy engine](../adrs/014-kyverno-as-policy-engine.md) (the broader decision +
  phased rollout; image verification is Phase 3)
- [ADR-050 — shared `build-sign.yml` reusable workflow](../adrs/050-shared-build-sign-reusable-workflow.md)
  (image + SBOM signing moved to a shared, app-team-unwritable signer; per-team gate via the caller-repo
  cert extension)
- [ADR-042 — isolated build provenance (SLSA L3)](../adrs/042-isolated-build-provenance-slsa-l3.md) (the
  same isolation pattern, already in place for provenance)
- [Kyverno policy catalog](kyverno-policy-catalog.md) (every policy, per cluster)
- [Kyverno break-glass runbook](../runbooks/kyverno-break-glass.md) (legitimate exceptions)
- `CLAUDE.md` → "Authoring Policy-Compliant Workloads" (the app-author checklist, incl. "images must be
  cosign-signed")
