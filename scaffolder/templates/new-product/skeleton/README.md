# app-${{ values.team }}-${{ values.product }}

Team `${{ values.team }}`'s **${{ values.product }}** product — scaffolded by the platform's **New Product** template
(ADR-067 v3), language **`${{ values.language }}`**. A minimal containerized HTTP service (`${{ values.service }}`)
plus the policy-compliant Kubernetes manifests and the thin CI that builds, signs, and ships it.

## What's here

| Path | Purpose |
|------|---------|
| the app source + its build manifest | Minimal `${{ values.language }}` HTTP service: `GET /healthz` (probe) + `GET /` (JSON) on `:8080`, graceful SIGTERM shutdown. No cloud deps. |
| `Dockerfile` | Multi-stage, **non-root**, multi-arch build → minimal (distroless where available) final image. The language-specific surface. |
| `k8s/base/` + `k8s/overlays/<stage>/` | Namespace-/host-agnostic `base/` + thin per-stage overlays (`dev`/`test`/`uat`/`staging`/`prod`). The per-Product ApplicationSet syncs `k8s/overlays/<stage>`, injecting the namespace + host; `deploy.yml` pins the dev overlay's image digest (promotion to other stages is by PR). Resources/probes are sized for `${{ values.language }}`. |
| `.github/workflows/` | `deploy.yml`/`preview.yml` (thin callers of `asanexample/trusted-ci`), `validate.yml` (overlay/ns guards + unit test), `security.yml` (Trivy + Semgrep). `dependabot.yml` keeps deps + base images current. |

## How the supply chain works

`deploy.yml` is a few small jobs that call shared, app-team-unwritable reusable workflows:

1. **build** → `trusted-ci/build-sign.yml` — builds the image, pushes it to the product-scoped repo
   `team-${{ values.team }}/${{ values.product }}-${{ values.service }}` in the platform ECR (via the per-Product OIDC role
   `github-actions-ecr-push-product-${{ values.team }}-${{ values.product }}`), cosign-keyless-signs it, attaches a
   CycloneDX SBOM.
2. **provenance** → `trusted-ci/slsa-provenance.yml` — attaches the SLSA build provenance (SLSA Build L3).
3. **deploy** — pins the freshly signed digest into `k8s/overlays/dev/kustomization.yaml` and commits it; the
   per-Product ApplicationSet syncs it. Promotion to test/uat/staging/prod is by PR (promote-by-PR).

Signatures, SBOM, and provenance carry this repo's identity (the `githubWorkflowRepository` cert extension),
which the platform's Kyverno `verify-images-product` / `verify-attestations-product` policies require at
admission. Nothing per-app to maintain — it lives in `trusted-ci`.

## Conventions (enforced by platform policy)

- **Do not** hardcode a hostname or namespace — the platform injects both (the ApplicationSet sets the
  destination namespace and patches the real host onto the `HTTPRoute`). Leave the `placeholder.invalid` host
  and the namespace-agnostic `base/`.
- Replace `cmd/`/`Dockerfile` with your real app — keep `/healthz` on `:8080`, or update the probes/port in
  `base/deployment.yaml`.
- A new Service for this product → add `k8s/base/<service>.yaml` + its image; a new Stage/Environment → use the
  **New Environment** portal template (authors `gitops/environments/${{ values.team }}/${{ values.product }}/<stage>.yaml`).

The team and product were registered in the platform repo — the `gitops/products/${{ values.team }}/${{ values.product }}.yaml`
registry entry and the `dev` Environment claim — by the same New Product run. See `docs/runbooks/app-supply-chain-onboarding.md`.
