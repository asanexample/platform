# Runbook — Onboard an App to the Supply-Chain Pipeline

**Audience:** an app team adding a new service repo (or retrofitting an existing one).
**Goal:** your CI builds an image, **signs** it, attaches an **SBOM** and **SLSA provenance**, and pins the
deploy manifest to the signed digest — so Kyverno admits your pods on the platform/preprod clusters.

> Why this matters: Kyverno runs `verify-images-team-<team>` and `verify-attestations-team-<team>` in
> **Enforce** mode in tenant namespaces. A pod whose image isn't signed (and attested) for **your team** is
> **rejected at admission**. Background: [`../architecture/supply-chain-overview.md`](../architecture/supply-chain-overview.md).

The supply-chain backbone is **not** copied into your repo. It lives in shared, app-team-**unwritable**
reusable workflows in **`asanexample/trusted-ci`** (public, but only the platform team can write to it):

- **`build-sign.yml`** — build from your Dockerfile → push to `team-<team>/<app>` ECR → cosign-keyless-sign
  the image → attach a CycloneDX SBOM. All under `trusted-ci`'s own OIDC identity.
- **`slsa-provenance.yml`** — attach the SLSA build provenance (SLSA L3 isolated signer, ADR-042).

Your repo just **calls** them. The reference implementation is **`app-bravo`** — the generic starter; copy it
and swap team/app/hostname/Dockerfile. (ADR-050.)

---

## Prerequisites (platform side — done by the platform team)

Before your CI can push or be trusted, your team must exist in the platform config. This is the
[tenant-onboarding runbook](tenant-onboarding.md) — confirm it's done:

1. **Team + app onboarded** — the `XTenant` claim defines the `team-<team>` namespace, the ECR repo
   `team-<team>/<app>`, and the route hostnames (`spec.domains` + the derived host); `teams.hcl` carries the
   per-team **signing identities** the policy will trust.
2. **ECR push role** — `arn:aws:iam::829808296602:role/github-actions-ecr-push-<team>`, trusting your repo's
   GitHub OIDC (see [ADR-036](../adrs/036-github-actions-oidc-federation.md)). `build-sign.yml` assumes this.
3. **Trust your team's shared-signer identity** — your repo (`asanexample/app-<team>`) listed in the policy
   unit's `shared_signer_teams` (→ `shared_signer_caller_repos`) **and** `isolated_provenance_teams`. That makes
   `verify-images` + the SBOM/provenance checks accept the shared `build-sign.yml` / `slsa-provenance.yml`
   identities **gated to your repo** by the cert's `githubWorkflowRepository` extension.

> **Bespoke builds (escape hatch):** if your build genuinely can't use `build-sign.yml` (exotic toolchain,
> multi-image, non-Docker), run your own build+sign job and ask the platform team to keep you on the
> **app-signed** path (`verify_subjects`, the `deploy.yml`/`preview.yml` identity) instead of the shared signer.
> The policy accepts whichever your team is wired for. This runbook covers the **shared (default)** path.

You **do not** create or manage any keys — signing is keyless (GitHub OIDC → Fulcio → Rekor).

---

## The workflows (thin callers — ~18 lines)

`deploy.yml` is three small jobs that call the shared workflows as **sibling 1-level jobs** (never nested) plus a
`deploy` job that pins the digest. Replace the `app:` value and (deliberately) the pinned `trusted-ci` SHA.

```yaml
name: Deploy
on:
  push:
    branches: [main]
permissions:
  id-token: write   # OIDC — AWS (ECR push) + cosign keyless signing (used inside build-sign.yml)
  contents: write   # the deploy job commits the pinned manifest

jobs:
  build:
    # avoid re-triggering on the deploy job's own manifest commit
    if: "!startsWith(github.event.head_commit.message, 'deploy:')"
    permissions:
      id-token: write
      contents: read
    uses: asanexample/trusted-ci/.github/workflows/build-sign.yml@<PINNED_SHA>
    with:
      app: <app>     # image is team-<team>/<app>; <team> is derived from your app-<team> repo name

  provenance:
    needs: build
    permissions:
      id-token: write
      contents: read
    uses: asanexample/trusted-ci/.github/workflows/slsa-provenance.yml@<PINNED_SHA>
    with:
      image: ${{ needs.build.outputs.image }}
      digest: ${{ needs.build.outputs.digest }}

  # Gated on BOTH build and provenance — guarantees every attestation exists before ArgoCD sees the digest.
  deploy:
    needs: [build, provenance]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: Pin manifest to the signed digest
        env:
          IMAGE: ${{ needs.build.outputs.image }}
          DIGEST: ${{ needs.build.outputs.digest }}
          SHA: ${{ github.sha }}
        run: |
          set -euo pipefail
          sed -i "s|image: .*|image: ${IMAGE}@${DIGEST}|" k8s/preprod/deployment.yaml
          # update ONLY the VERSION env value (the line after `- name: VERSION`)
          sed -i "/- name: VERSION/{n;s|value: \".*\"|value: \"${SHA}\"|}" k8s/preprod/deployment.yaml
      - name: Commit + push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s/preprod/deployment.yaml
          git diff --cached --quiet || git commit -m "deploy: update image to ${{ github.sha }}"
          git push
```

**PR previews:** a near-identical `preview.yml` triggered on `pull_request` — the same `build` + `provenance`
jobs, no `deploy` job, tagging with `github.event.pull_request.head.sha`. (Reference: `app-bravo/preview.yml`.)
Fork PRs receive no OIDC token, so they fail closed (cannot push) — by design.

The Dockerfile is the **only** language/framework-specific surface you own; `build-sign.yml` exposes
`context` / `dockerfile` / `build-args` / `target` / `platforms` inputs for common build variation.

---

## Checklist

- [ ] `deploy.yml`/`preview.yml` **call** `build-sign.yml` + `slsa-provenance.yml`; you do **not** copy
      build/sign/SBOM/provenance steps into your repo.
- [ ] Both reusable workflows pinned to a **full commit SHA** (bump deliberately — that's your supply-chain pin).
- [ ] `permissions.id-token: write` on the `build` and `provenance` caller jobs (passed through to the reusable
      workflow for OIDC); `contents: write` on the `deploy` job.
- [ ] `with.app` is exactly `<app>` from `teams.hcl` (the image becomes `team-<team>/<app>`; the team is derived
      from your `app-<team>` repo name, so cross-team pushes are structurally impossible).
- [ ] `deploy` job `needs: [build, provenance]` (the barrier — ArgoCD never sees an unprovenanced digest).
- [ ] A **Dockerfile** at the repo root (or pass `dockerfile:`); the image runs as non-root on a slim base.
- [ ] Your manifests live under `k8s/` and are policy-compliant — see the CLAUDE.md "Authoring Policy-Compliant
      Workloads" checklist (resource limits, probes, ClusterIP, named ServiceAccount, allow-listed hostnames,
      no `:latest`).
- [ ] Platform team has added your repo to `shared_signer_teams` + `isolated_provenance_teams` (prereq 3).

---

## Verify it worked

The shared workflow signs under **its own** identity; your team is the `githubWorkflowRepository` cert extension.

```bash
IMAGE=829808296602.dkr.ecr.us-east-1.amazonaws.com/team-<team>/<app>
DIGEST=sha256:...        # the digest the deploy job pinned into k8s/preprod/deployment.yaml
ISSUER=https://token.actions.githubusercontent.com

# Image signature — shared build-sign.yml subject, gated to YOUR repo by the extension.
cosign verify "$IMAGE@$DIGEST" \
  --certificate-identity-regexp '^https://github\.com/asanexample/trusted-ci/\.github/workflows/build-sign\.yml@' \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-github-workflow-repository asanexample/app-<team>

# SBOM — same shared build-sign.yml identity.
cosign verify-attestation "$IMAGE@$DIGEST" --type cyclonedx \
  --certificate-identity-regexp '^https://github\.com/asanexample/trusted-ci/\.github/workflows/build-sign\.yml@' \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-github-workflow-repository asanexample/app-<team>

# Provenance — shared slsa-provenance.yml identity, same extension.
cosign verify-attestation "$IMAGE@$DIGEST" --type slsaprovenance \
  --certificate-identity-regexp '^https://github\.com/asanexample/trusted-ci/\.github/workflows/slsa-provenance\.yml@' \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-github-workflow-repository asanexample/app-<team>

# On-cluster: did the pod get admitted?
kubectl --context preprod -n team-<team> get pods
```

If a pod is **denied**, the message names the failing policy. See
[`supply-chain-incidents.md`](supply-chain-incidents.md) → "A pod is denied at admission" for the diagnosis tree.

---

## Common mistakes (and the symptom)

| Mistake | Symptom |
|---------|---------|
| Reusable workflow pinned to an unreachable/typo'd SHA or repo | `error parsing called workflow … : workflow was not found` at startup (0 jobs) |
| Missing `id-token: write` on the caller job | inside `build-sign.yml`: cosign `no identity token` / AWS `Not authorized to perform sts:AssumeRoleWithWebIdentity` |
| `with.app` ≠ `teams.hcl` app / wrong team repo name | `build-sign.yml` guard refuses (image not in `team-<team>/*`); or `image-registries` denies the pod |
| Platform hasn't added you to `shared_signer_teams` | signature is valid but **no team policy trusts the shared identity for you** → pod denied |
| Copied the *old* per-app build+sign steps AND call the shared signer | two image-signature identities; prefer the thin caller (delete the inline build/sign) |
| Build job self-attests `slsaprovenance` (legacy) | two provenance identities → Kyverno single-identity match fails (`verifiedCount: 0`) — provenance is `slsa-provenance.yml`'s job only |
| Sigstore egress blocked in the runner | cosign `sign`/`attest` hangs/fails reaching `fulcio.sigstore.dev` / `rekor.sigstore.dev` |

---

## Related

- Architecture & SLSA matrix: [`../architecture/supply-chain-overview.md`](../architecture/supply-chain-overview.md)
- Keyless signing deep dive: [`../architecture/cosign-image-signing.md`](../architecture/cosign-image-signing.md)
- Shared signer + heterogeneity model: [ADR-050](../adrs/050-shared-build-sign-reusable-workflow.md)
- Provenance design (L3): [ADR-042](../adrs/042-isolated-build-provenance-slsa-l3.md)
- What's enforced where: [`../architecture/kyverno-policy-catalog.md`](../architecture/kyverno-policy-catalog.md)
- Incident response: [`supply-chain-incidents.md`](supply-chain-incidents.md)
- Tenant/infra onboarding: [`tenant-onboarding.md`](tenant-onboarding.md)
