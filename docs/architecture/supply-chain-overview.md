# Software Supply-Chain Security — Overview

This is the **map** of the platform's software supply chain: *why* it exists, the *end-to-end flow* from a
developer's `git push` to a running pod, *how the pieces fit together* (SBOM, cosign signatures, SLSA
provenance, Fulcio, Rekor, Kyverno), and *which SLSA level* we actually achieve.

It is deliberately a high-level integration story. The deep dives live elsewhere and are linked inline:

- **Keyless signing mechanics** (OIDC → Fulcio → Rekor, per-team identity): [`cosign-image-signing.md`](cosign-image-signing.md)
- **SLSA Build L3 design** (the isolated `trusted-ci` provenance signer): [ADR-042](../adrs/042-isolated-build-provenance-slsa-l3.md)
- **Shared image + SBOM signer** (the isolated `trusted-ci/build-sign.yml` reusable workflow; app repos as thin callers): [ADR-050](../adrs/050-shared-build-sign-reusable-workflow.md)
- **Policy engine** (Kyverno, audit→enforce rollout): [ADR-014](../adrs/014-kyverno-as-policy-engine.md)
- **What's enforced per cluster**: [`kyverno-policy-catalog.md`](kyverno-policy-catalog.md)
- **Onboard an app to the pipeline**: [`../runbooks/app-supply-chain-onboarding.md`](../runbooks/app-supply-chain-onboarding.md)
- **When something breaks**: [`../runbooks/supply-chain-incidents.md`](../runbooks/supply-chain-incidents.md)

---

## 1. Why we do this (threat model)

A container image is a black box: by the time it reaches the cluster, nothing about the artifact itself
tells you *who built it*, *from what source*, or *whether it was tampered with in transit*. This platform
is multi-tenant — many teams push to one shared ECR and deploy to shared clusters — so "trust the registry"
is not good enough. The supply chain answers four questions at **admission time**, for every pod:

| Threat | Without controls | Control |
|--------|------------------|---------|
| **Tampered / unknown image** — an attacker pushes a malicious image (or swaps a digest) and it gets deployed | Any image in ECR runs | **cosign signature** — only images signed by a known CI identity are admitted |
| **Cross-tenant image use** — team B runs team A's image (or pushes into A's repo) | Namespace isolation only; images are shared | **Per-team signing identity** — `verify-images-team-<team>` admits only images signed by the shared `trusted-ci/build-sign.yml` workflow whose `githubWorkflowRepository` cert extension is `app-<team>` (ADR-050); a bespoke-build app's own workflow is a supported fallback |
| **No proof of origin** — "where did this image come from? what's in it?" is unanswerable | Opaque | **SLSA provenance + SBOM** attestations — signed statements of *how* it was built and *what's inside* |
| **Forged image / provenance / SBOM** — a compromised app build signs its own malicious artifact and claims "I am a trusted build" | Self-signing/self-attestation proves nothing | **Isolated signer** (`trusted-ci`) — image + SBOM signing (`build-sign.yml`) and provenance (`slsa-provenance.yml`) run in a trust domain the app's own build cannot assume; per-team gating is the `githubWorkflowRepository` cert extension (ADR-042, ADR-050) |

**Drivers.** This is a reference Internal Developer Platform; supply-chain integrity is table stakes for the
compliance tiers it models (see [ADR-013 compliance-tier model](../adrs/013-compliance-tier-model.md)) and
maps directly to the CNCF "secure software supply chain" capability and SLSA. The controls are **defense in
depth on the deploy path**, complementary to the shift-left scanning (Trivy/Semgrep) that runs in app CI and
PR-time policy checks ([`kyverno-shift-left.md`](kyverno-shift-left.md)).

---

## 2. The end-to-end flow

One commit to an app repo's `main` produces a signed, attested, provenance-bearing image that Kyverno
admits — with **no window** where ArgoCD could deploy an image whose attestations don't yet exist.

```text
 DEVELOPER                 APP CI — app-<team> repo's deploy.yml/preview.yml is a THIN CALLER (ADR-050)
 ─────────                 ───────────────────────────────────────────────────────────────
 git push main  ─────────▶ build-sign job  (uses asanexample/trusted-ci/...build-sign.yml@<pinned-sha>)
                             1. assume role github-actions-ecr-push-<team>  (OIDC → AWS, ADR-036)
                             2. docker build + push  →  ECR team-<team>/<app>:<sha>
                             3. cosign sign   <repo>@<digest>           (keyless: OIDC → Fulcio cert → Rekor)
                             4. syft → CycloneDX SBOM
                                cosign attest --type cyclonedx          (keyless, same workflow)
                                ↳ signed by the ISOLATED trusted-ci build-sign.yml identity the app
                                  cannot assume; per-team gate = githubWorkflowRepository = app-<team> (ADR-050)
                           provenance job  (uses asanexample/trusted-ci/...slsa-provenance.yml@<pinned-sha>)
                             5. → SLSA provenance (slsa.dev/provenance/v0.2), signed by the same
                                  ISOLATED trusted-ci trust domain the app build cannot forge (ADR-042)
                           deploy job  (needs: [build-sign, provenance])  ← barrier: all attestations exist
                             6. pin k8s manifest to <repo>@<digest>, git commit + push
                                                                         │
 ┌───────────────────────────────────────────────────────────────────── ▼ ─────────────┐
 │ Sigstore (public-good)            ECR (platform acct 829…)            ArgoCD          │
 │  Fulcio  = short-lived cert        image + .att attestations          7. syncs the    │
 │  Rekor   = transparency log        (signature, SBOM, provenance)         pinned digest │
 └───────────────────────────────────────────────────────────────────── │ ─────────────┘
                                                                          ▼
 KYVERNO admission (platform + preprod clusters)   ◀── Pod create in team-<team> namespace
   verify-images-team-<team>        : image signed by trusted-ci build-sign.yml,        (Enforce)
                                      githubWorkflowRepository = app-<team>? (or app fallback)
   verify-attestations-team-<team>  : CycloneDX SBOM present + signed by build-sign.yml? (audit→Enforce)
                                      SLSA provenance present + signed by trusted-ci? (per ADR-042/050)
   → admit (mutate image to digest) ──▶ Pod runs        |        → deny ──▶ Pod rejected at admission
```

The **`needs: [build-sign, provenance]` barrier on the deploy job is load-bearing**: the digest ArgoCD picks up
already carries its signature, SBOM, *and* provenance, so Kyverno's Enforce-mode `verify-attestations` never
sees an image whose attestations are still in flight.

---

## 3. How the pieces fit together

Each mechanism answers a different question; together they form a verifiable chain anchored in a
**short-lived certificate identity**, not a long-lived key.

| Piece | What it is | What it proves | Where it lives |
|-------|-----------|----------------|----------------|
| **cosign signature** | A signature over the image **digest** | The image is exactly this bytes-for-bytes artifact, signed by a known identity | ECR, next to the image (`sha256-<digest>.sig` / `.att`) |
| **Fulcio** | Sigstore's CA | Issues a **10-minute** X.509 cert binding the signature to the **GitHub OIDC identity** (the workflow ref) — no private key to steal or rotate | Sigstore public-good (`fulcio.sigstore.dev`) |
| **Rekor** | Sigstore's append-only **transparency log** | The signature existed at a point in time (tamper-evident, publicly auditable) — verification needs no shared secret | Sigstore public-good (`rekor.sigstore.dev`) |
| **SBOM** | CycloneDX inventory (Syft) | *What's inside* the image — every package/version, for vuln triage and audit | cosign **attestation** on the image (`--type cyclonedx`, `cyclonedx.org/bom`) |
| **SLSA provenance** | A signed statement of *how* the image was built | Build origin/parameters; at L3, signed by an **isolated** builder identity (ADR-042) | cosign **attestation** (`slsa.dev/provenance/v0.2`) |
| **Kyverno** | Admission policy engine | Enforces all of the above **at deploy time**, per team | `policy` module, both clusters |

**The trust anchor is the identity, not a key.** Kyverno doesn't hold a public key to check against. It
verifies that the Fulcio cert on each signature/attestation was issued to the **expected GitHub workflow
identity** (`issuer: https://token.actions.githubusercontent.com`, `subject: <workflow ref>`) and that the
entry is in **Rekor**. Since the image + SBOM are now signed by the shared
`trusted-ci/build-sign.yml` reusable workflow (ADR-050), the cert **subject** is the same for every
team; **per-team isolation moves to the `githubWorkflowRepository` cert extension**, which Fulcio sets
from the *calling* app repo's OIDC and which one team cannot forge for another. So `app-alpha`'s images
carry `githubWorkflowRepository: …/app-alpha`, which `app-bravo`'s policy does not list. (App-signed
identities remain a supported fallback for bespoke-build apps.) See
[`cosign-image-signing.md`](cosign-image-signing.md) for the full keyless mechanics.

**Predicate types must match end-to-end.** The shared `trusted-ci/build-sign.yml` job emits
`cosign attest --type cyclonedx` (`https://cyclonedx.org/bom`) and the `trusted-ci/slsa-provenance.yml`
job emits `slsa.dev/provenance/v0.2`; Kyverno's
`verify-attestations-team-<team>` requires *exactly* those predicate types. A mismatch (e.g. cosign v3's new
bundle format vs. Kyverno's default attestor) is a silent rejection — which is why the app pins **cosign
v2.5.2** for the legacy `.att` format (see the onboarding runbook).

---

## 4. The two verification policies (what Kyverno actually checks)

Both are generated per team from `teams.hcl` (`verifySubjects`, `tenantRegistryMap`, `attestCallerRepos`) by
the `policy` module, plus the module-level `trusted_ci_build_subject_regexp` + `shared_signer_caller_repos`
inputs that admit the shared `build-sign.yml` signer (ADR-050). Each has its **own**
`validationFailureAction`/`failurePolicy` so signatures can be **Enforce** while attestations roll out
**Audit-first**. `webhookTimeoutSeconds: 30` covers the signature fetch + Rekor lookup.

**`verify-images-team-<team>`** (signatures) — `infra/modules/policy/policies-chart/templates/verify-images.yaml`

- Scope: Pods in `team-<team>` using images under the team's ECR repo (`tenantRegistryMap[team]/*`).
- Admits an image signed (keyless) by **any one** (`count: 1`) of these alternatives: the shared
  **`trusted-ci/build-sign.yml`** signer (`trusted_ci_build_subject_regexp`) gated per-team by the cert's
  **`githubWorkflowRepository`** extension = the team's caller repo (`shared_signer_caller_repos`, ADR-050)
  — **or**, as a bespoke-build fallback, the team's own app identity: the stable `deploy_subject`
  (main-branch workflow) **or** the `preview_subject_regexp` (PR previews — the OIDC ref varies per PR, so
  it's matched by regex).
- On **Enforce**, `mutateDigest: true` pins the admitted image to its digest (Kyverno forbids mutation in
  Audit, so pinning only happens once enforcing).

**`verify-attestations-team-<team>`** (SBOM + provenance) — `.../verify-attestations.yaml`

- Requires two attestations on the image:
  - **SBOM** (`https://cyclonedx.org/bom`). Accepts (`count: 1`) the shared **`trusted-ci/build-sign.yml`**
    signer (`trusted_ci_build_subject_regexp`, gated per-team by the **`githubWorkflowRepository`**
    extension = the team's caller repo, ADR-050) — **or**, as a fallback, the team's own workflow identity.
  - **SLSA provenance** (`https://slsa.dev/provenance/v0.2`). For teams that have adopted the isolated
    signer (those in `attestCallerRepos`), it must be signed by the **`trusted-ci`** reusable workflow
    (`trustedCiSubjectRegExp`), gated per-team by the cert's **`githubWorkflowRepository`** extension = the
    team's caller repo. A different team can't forge that extension — Fulcio sets it from the *calling*
    repo's OIDC. Teams not yet adopted keep app-signed provenance.
- Does **not** mutate (`mutateDigest: false`) — `verify-images` already pins the digest.

---

## 5. SLSA compliance matrix

We target **SLSA Build Level 3** (provenance exists, is authentic, and is produced by a build platform whose
provenance the tenant cannot forge). Status against [SLSA v1.0 Build track](https://slsa.dev/spec/v1.0/levels):

| SLSA Build requirement | Status | How / why |
|------------------------|:------:|-----------|
| **L1 — Provenance exists** | ✅ | Every image carries a `slsa.dev/provenance/v0.2` attestation (the `provenance` job). |
| **L1 — Provenance distributed** | ✅ | Attached to the image in ECR; fetched by Kyverno at admission. |
| **L2 — Provenance is authenticated** (signed) | ✅ | Keyless cosign signature, verifiable via Fulcio cert identity + Rekor — no shared key. |
| **L2 — Hosted build platform** | ✅ | GitHub-hosted Actions runners (ephemeral, GitHub-managed). |
| **L3 — Provenance is unforgeable** (build identity isolated from tenant) | ✅ | Provenance is signed by the **isolated `asanexample/trusted-ci`** reusable workflow, a Fulcio identity the app's own build job cannot assume; the app no longer self-attests provenance (ADR-042). The per-team gate is the `githubWorkflowRepository` cert extension, set by Fulcio from the caller's OIDC. |
| **L3 — Isolated build environment** (secrets/runner isolation) | ⚠️ Partial | GitHub Actions provides per-job ephemeral runners + OIDC isolation; we do **not** run the dedicated SLSA `slsa-github-generator` (rejected for ECR credential-passing reasons — ADR-042 §"Why not off-the-shelf"). The isolation we rely on is the OIDC identity boundary, not a separate signing enclave. |

**Beyond the Build track:** image **signatures** (integrity + per-team identity) and the **CycloneDX SBOM**
are layered on top — these aren't SLSA *levels* but are part of the same admission gate. Both are now
signed by the **same isolated `trusted-ci/build-sign.yml`** identity the app build cannot assume
(per-team gating via the `githubWorkflowRepository` cert extension, ADR-050), so they inherit the same
tenant-cannot-forge property as the L3 provenance rather than relying on the app's own self-signing.
Source-track and reproducible-build requirements are **out of scope** today.

**Rollout state:** signatures (`verify-images`) are **Enforce** on preprod + platform. Attestations
(`verify-attestations`, incl. the L3 trusted-ci provenance) are **Enforce on preprod**; consult
[`kyverno-policy-catalog.md`](kyverno-policy-catalog.md) for the authoritative per-cluster status. The
shared `trusted-ci/build-sign.yml` image + SBOM signer (ADR-050) went **live on preprod (Enforce) on
2026-06-03**, with `alpha` and `bravo` migrated to thin-caller `deploy.yml`/`preview.yml` (`app-bravo` is
the generic reference).

---

## 6. What is *not* covered (gaps & boundaries)

- **SBOM consumption** — SBOMs are generated, signed, and required at admission, but are not yet
  automatically scanned for vulns post-build or surfaced in a dashboard. (Trivy runs on dependencies in app
  CI separately — [`kyverno-shift-left.md`](kyverno-shift-left.md).)
- **Source track / reproducible builds** — not attempted; we attest the *build*, not bit-for-bit
  reproducibility.
- **Sigstore is a hard dependency** — verification needs egress to Fulcio + Rekor. If they're unreachable,
  Kyverno verification fails closed (Enforce) — see the [incidents runbook](../runbooks/supply-chain-incidents.md).
- **Regulated tiers** (HIPAA/PCI) layer additional controls on top — see [ADR-013](../adrs/013-compliance-tier-model.md).
