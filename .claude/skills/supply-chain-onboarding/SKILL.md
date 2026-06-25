---
name: supply-chain-onboarding
description: >-
  How to wire an app's GitHub Actions CI so its images pass this platform's Kyverno cosign
  verification — the thin-caller model over the shared trusted-ci signing/provenance workflows.
  Use when setting up or fixing an app repo's deploy.yml / preview.yml, debugging a
  verify-images / verify-attestations admission failure, or onboarding a product's supply chain.
  Covers the pinned-SHA reusable-workflow calls, the id-token permissions, the build→provenance
  barrier, the registry-derived trust (no allow-list), and the by-hand cosign verify commands.
  This is the CI-WIRING side; the manifest side is authoring-k8s-workloads.
---

# Supply-chain onboarding (app CI)

Images that run in environment namespaces must be **cosign-signed and attested**, verified at
admission by `verify-images-product-<team>-<product>` and `verify-attestations-product-<team>-<product>`
(**Enforce on preprod**). An app team does **not** implement signing — its CI is a *thin caller*
of shared, app-team-unwritable reusable workflows. Source of truth:
`docs/runbooks/app-supply-chain-onboarding.md`, `docs/architecture/cosign-image-signing.md`, and
the scaffolder skeleton under `scaffolder/templates/new-product/skeleton/.github/workflows/`.

## The thin-caller model

The app's `deploy.yml` / `preview.yml` are small wrappers whose jobs **call** the shared
workflows (build → sign → SBOM, then provenance), pinned to a full commit SHA:

```yaml
permissions:
  id-token: write        # OIDC — keyless cosign signing + AWS ECR push; stamps the cert's
  contents: read         # githubWorkflowRepository extension with THIS repo (the per-product gate)

jobs:
  build:
    permissions: { id-token: write, contents: read }
    uses: asanexample/trusted-ci/.github/workflows/build-sign.yml@<PINNED_SHA>
    with: { app: <product>-<svc>, product: <product>, tag: ${{ github.sha }} }   # image → team-<team>/<product>-<svc>

  provenance:
    needs: build
    permissions: { id-token: write, contents: read }
    uses: asanexample/trusted-ci/.github/workflows/slsa-provenance.yml@<PINNED_SHA>
    with: { image: ${{ needs.build.outputs.image }}, digest: ${{ needs.build.outputs.digest }}, product: <product> }

  promote:                 # (or `deploy`) — pins the signed @digest into the manifest
    needs: [build, provenance]   # the BARRIER: nothing ships until both attestations exist
```

- **Pin to a full SHA** — that pin *is* your supply-chain trust anchor; bump it deliberately.
- **`needs: [build, provenance]`** on the promote/deploy job is the barrier — the digest that
  reaches ArgoCD already carries signature, SBOM, and provenance.
- The exact `with:` inputs follow the shared workflow's interface (the scaffolder skeleton is the
  canonical starter — copy it rather than hand-rolling). `preview.yml` is the same build+provenance
  on `pull_request`, no promote; fork PRs get no OIDC token and fail closed by design.

## What you own vs what's provided

You own **only the Dockerfile** (runs non-root on a slim base) and the thin caller. Build, cosign
signing, SBOM (CycloneDX), and SLSA L3 provenance all run inside `asanexample/trusted-ci` under
its own identity — **do not copy those steps into your repo**.

## Trust is registry-derived — there is no allow-list to edit

Set **`spec.repo`** in your Product registry entry (`gitops/products/<team>/<product>.yaml`) to
your app repo. The `policy` unit then derives `verify_subjects_product` from it automatically, and
the Kyverno policy admits the shared `build-sign.yml` signer **gated to your product** by the
cert's `githubWorkflowRepository` extension (= your repo). Fulcio sets that extension from the
*caller's* OIDC, so another product can't forge it — its image is rejected. A per-product
app-signed identity (your `deploy.yml`/`preview.yml`) is an accepted **fallback** for bespoke
builds. Once `spec.repo` is set and `policy` is applied, trust is live; nothing else to register.

## Verify by hand

```bash
IMAGE=829808296602.dkr.ecr.us-east-1.amazonaws.com/team-<team>/<product>-<svc>
DIGEST=sha256:...
ISSUER=https://token.actions.githubusercontent.com

cosign verify "$IMAGE@$DIGEST" \
  --certificate-identity-regexp '^https://github\.com/asanexample/trusted-ci/\.github/workflows/build-sign\.yml@' \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-github-workflow-repository asanexample/<team>-<product>

# attestations: same flags with `cosign verify-attestation --type cyclonedx` (SBOM) and
# `--type slsaprovenance` (provenance; identity-regexp uses slsa-provenance.yml).
```

## Onboarding checklist

- [ ] `deploy.yml`/`preview.yml` **call** `build-sign.yml` + `slsa-provenance.yml` (don't copy steps)
- [ ] Both pinned to a **full commit SHA**
- [ ] `permissions.id-token: write` on the `build` and `provenance` jobs
- [ ] `with` product/service match your `<team>-<product>` repo (image becomes `team-<team>/<product>-<svc>`)
- [ ] promote/deploy job `needs: [build, provenance]`
- [ ] A Dockerfile at repo root; manifests under `k8s/` are policy-compliant (see authoring-k8s-workloads)
- [ ] Product registry `spec.repo` set to your app repo, and `policy` applied

## References

- `docs/runbooks/app-supply-chain-onboarding.md` — the onboarding procedure + common mistakes
- `docs/architecture/cosign-image-signing.md` — the keyless trust model deep-dive
- `scaffolder/templates/new-product/skeleton/.github/workflows/` — the starter deploy.yml/preview.yml
- Related skills: **authoring-k8s-workloads** (manifests), **environment-onboarding** (the Product/registry side)
