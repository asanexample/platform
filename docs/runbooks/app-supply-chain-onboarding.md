# Runbook — Onboard an App to the Supply-Chain Pipeline

**Audience:** an app team adding a new service repo (or retrofitting an existing one).
**Goal:** your CI builds an image, **signs** it, attaches an **SBOM** and **SLSA provenance**, and pins the
deploy manifest to the signed digest — so Kyverno admits your pods on the platform/preprod clusters.

> Why this matters: Kyverno runs `verify-images-team-<team>` and `verify-attestations-team-<team>` in
> **Enforce** mode in tenant namespaces. A pod whose image isn't signed (and attested) by **your team's**
> CI identity is **rejected at admission**. Background: [`../architecture/supply-chain-overview.md`](../architecture/supply-chain-overview.md).

The reference implementation is **`app-alpha`** (`.github/workflows/deploy.yml` and `preview.yml`). This
runbook is the generalized version of those workflows.

---

## Prerequisites (platform side — done by the platform team)

Before your CI can push or be trusted, your team must exist in the platform config. This is the
[tenant-onboarding runbook](tenant-onboarding.md) — confirm it's done:

1. **Team + app in `teams.hcl`** — defines `team-<team>` namespace, the ECR repo `team-<team>/<app>`, the
   team's `hostnames`, and the **signing subjects** (`verifySubjects`: the `deploy_subject` and
   `preview_subject_regexp` that name *your repo's workflows*). If these don't list your repo, Kyverno won't
   trust your signatures.
2. **ECR push role** — `arn:aws:iam::829808296602:role/github-actions-ecr-push-<team>`, trusting your repo's
   GitHub OIDC (see [ADR-036](../adrs/036-github-actions-oidc-federation.md)).
3. **Trusted-CI provenance (SLSA L3)** — your repo listed in `attestCallerRepos` so the isolated
   `trusted-ci` provenance is trusted for your team (ADR-042). If not yet adopted, the team falls back to
   app-signed provenance — coordinate with the platform team.

You **do not** create or manage any keys — signing is keyless (GitHub OIDC → Fulcio → Rekor).

---

## The workflow (copy + adapt)

Three jobs: **build** (build → push → sign → SBOM), **provenance** (isolated trusted-ci signer), **deploy**
(pin the digest + commit). Replace `<team>`, `<app>`, and the `trusted-ci` pin.

```yaml
name: Deploy
on:
  push:
    branches: [main]

permissions:
  id-token: write   # OIDC — required for BOTH AWS (ECR push) and cosign keyless signing
  contents: write   # the deploy job commits the pinned manifest

env:
  ECR_REGISTRY: 829808296602.dkr.ecr.us-east-1.amazonaws.com
  ECR_REPO: team-<team>/<app>          # MUST match teams.hcl — cross-team repos are denied

jobs:
  build:
    runs-on: ubuntu-latest
    # avoid re-triggering on the deploy job's own manifest commit
    if: "!startsWith(github.event.head_commit.message, 'deploy:')"
    permissions:
      id-token: write
      contents: read
    # NOTE: workflow-level `env` is NOT visible in job `outputs:` — surface the image ref via a step.
    outputs:
      image: ${{ steps.img.outputs.image }}
      digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::829808296602:role/github-actions-ecr-push-<team>
          aws-region: us-east-1
      - uses: aws-actions/amazon-ecr-login@v2
      - uses: docker/setup-buildx-action@v3

      - name: Build and push image
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPO }}:${{ github.sha }}

      - name: Expose image ref for later jobs
        id: img
        run: echo "image=${ECR_REGISTRY}/${ECR_REPO}" >> "$GITHUB_OUTPUT"

      - name: Install cosign
        uses: sigstore/cosign-installer@v3
        with:
          cosign-release: "v2.5.2"   # PIN v2 — legacy .att format that Kyverno's default attestor verifies

      # Keyless signature over the DIGEST (never a tag). OIDC → Fulcio cert → Rekor log.
      - name: Sign image (cosign keyless)
        run: cosign sign --yes "${ECR_REGISTRY}/${ECR_REPO}@${{ steps.build.outputs.digest }}"

      - name: Install Syft (pinned + checksum-verified)
        env:
          SYFT_VERSION: "1.44.0"
        run: |
          base="https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}"
          asset="syft_${SYFT_VERSION}_linux_amd64.tar.gz"
          curl -sfL "${base}/${asset}" -o "${asset}"
          curl -sfL "${base}/syft_${SYFT_VERSION}_checksums.txt" -o syft_checksums.txt
          grep " ${asset}\$" syft_checksums.txt | sha256sum -c -
          tar xzf "${asset}" syft && sudo install -m 0755 syft /usr/local/bin/syft

      - name: Generate + attest SBOM (CycloneDX, keyless)
        run: |
          IMAGE="${ECR_REGISTRY}/${ECR_REPO}@${{ steps.build.outputs.digest }}"
          syft "$IMAGE" -o cyclonedx-json=sbom.cdx.json
          cosign attest --yes --type cyclonedx --predicate sbom.cdx.json "$IMAGE"

  # SLSA Build L3 — provenance signed by the ISOLATED trusted-ci identity (your build can't forge it).
  # Pin to a full commit SHA (not a tag). This is the SOLE provenance source — do NOT also self-attest
  # slsaprovenance in the build job (two identities break Kyverno's single-identity attestation match).
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
        run: |
          sed -i "s|image: .*|image: ${IMAGE}@${DIGEST}|" k8s/preprod/deployment.yaml
          # update ONLY the VERSION env value (the line after `- name: VERSION`)
          sed -i "/- name: VERSION/{n;s|value: \".*\"|value: \"${{ github.sha }}\"|}" k8s/preprod/deployment.yaml
      - name: Commit + push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s/preprod/deployment.yaml
          git diff --cached --quiet || git commit -m "deploy: update image to ${{ github.sha }}"
          git push
```

**PR previews:** add a near-identical `preview.yml` triggered on `pull_request`, tagging with
`github.event.pull_request.head.sha`. The OIDC identity differs per PR ref — that's why Kyverno matches
previews via `preview_subject_regexp` rather than an exact subject. (Reference: `app-alpha/preview.yml`.)

---

## Checklist

- [ ] `permissions.id-token: write` at the **job** level (build + provenance). Missing this = no OIDC token
      = cosign can't sign and AWS role assumption fails.
- [ ] `ECR_REPO` is exactly `team-<team>/<app>` from `teams.hcl` (cross-team repos are denied by
      `image-registries` policy).
- [ ] **Sign the digest**, never a tag (`@${digest}`, not `:${sha}`). Tags are mutable; the signature must
      bind the immutable artifact.
- [ ] **cosign pinned to v2.x** (`v2.5.2`). v3's bundle format needs a coordinated Kyverno change (#114).
- [ ] **Syft pinned + checksum-verified**; SBOM is **CycloneDX** (`-o cyclonedx-json`), attested with
      `--type cyclonedx`.
- [ ] Provenance via the **`trusted-ci` reusable workflow pinned to a full SHA** — and the build job does
      **not** self-attest `slsaprovenance`.
- [ ] `deploy` job `needs: [build, provenance]` (the barrier).
- [ ] Your manifests live under `k8s/` and are otherwise policy-compliant — see the CLAUDE.md "Authoring
      Policy-Compliant Workloads" checklist (resource limits, probes, ClusterIP, named ServiceAccount,
      allow-listed hostnames, no `:latest`).

---

## Verify it worked

```bash
IMAGE=829808296602.dkr.ecr.us-east-1.amazonaws.com/team-<team>/<app>
DIGEST=sha256:...        # from the build job output / ECR

# Signature present + from your workflow identity?
cosign verify "$IMAGE@$DIGEST" \
  --certificate-identity-regexp "https://github.com/asanexample/app-<team>/.github/workflows/.+" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# Attestations present? (SBOM + provenance predicate types)
cosign verify-attestation "$IMAGE@$DIGEST" --type cyclonedx \
  --certificate-identity-regexp "https://github.com/asanexample/app-<team>/.+" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
cosign verify-attestation "$IMAGE@$DIGEST" --type slsaprovenance \
  --certificate-identity-regexp "https://github.com/asanexample/trusted-ci/.+" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# On-cluster: did the pod get admitted (and its image pinned to a digest by Kyverno)?
kubectl --context preprod -n team-<team> get pods
```

If a pod is **denied**, the message names the failing policy. See
[`supply-chain-incidents.md`](supply-chain-incidents.md) → "A pod is denied at admission" for the diagnosis
tree.

---

## Common mistakes (and the symptom)

| Mistake | Symptom |
|---------|---------|
| Forgot `id-token: write` | cosign: `signing failed: getting key from … no identity token`; AWS: `Not authorized to perform sts:AssumeRoleWithWebIdentity` |
| Signed the **tag** not the digest | Kyverno admits nothing — `verifyImages` checks the resolved digest; `cosign verify` finds no signature on the digest |
| cosign **v3** used | `verify-attestation` / Kyverno reports no matching attestation (new bundle format ≠ default attestor) → `verifiedCount: 0` |
| Build job **also** self-attests provenance | Two `slsaprovenance` identities → Kyverno single-identity match fails (`verifiedCount: 0`) — remove the self-attest, rely only on `trusted-ci` |
| `ECR_REPO` ≠ `teams.hcl` repo | `image-registries` policy denies the pod (cross-team / unknown registry) |
| `teams.hcl` `verifySubjects` doesn't list this repo | Signature is valid but **no team policy trusts it** → denied. Fix in `teams.hcl` (platform team). |
| Sigstore egress blocked in the runner | cosign `sign`/`attest` hangs/fails reaching `fulcio.sigstore.dev` / `rekor.sigstore.dev` |

---

## Related

- Architecture & SLSA matrix: [`../architecture/supply-chain-overview.md`](../architecture/supply-chain-overview.md)
- Keyless signing deep dive: [`../architecture/cosign-image-signing.md`](../architecture/cosign-image-signing.md)
- Provenance design (L3): [ADR-042](../adrs/042-isolated-build-provenance-slsa-l3.md)
- What's enforced where: [`../architecture/kyverno-policy-catalog.md`](../architecture/kyverno-policy-catalog.md)
- Incident response: [`supply-chain-incidents.md`](supply-chain-incidents.md)
- Tenant/infra onboarding: [`tenant-onboarding.md`](tenant-onboarding.md)
