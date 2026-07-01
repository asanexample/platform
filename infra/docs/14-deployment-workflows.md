# Deployment Workflows

## Overview

The platform has **two deployment tracks**, deliberately separated:

1. **Infrastructure (this repo)** — OpenTofu/Terragrunt, applied by a human-gated
   plan→review→apply flow (no auto-apply on merge). CI validates and security-scans every PR.
2. **Application workloads (app repos, e.g. `app-alpha`)** — container images built in CI and
   delivered by **GitOps**: CI pins a signed image digest into the app's `k8s/` manifests, and
   **ArgoCD** syncs the cluster to match. Kyverno enforces supply-chain policy at admission.

This split keeps infrastructure changes auditable and manually gated while letting application
deployments flow automatically once they pass policy.

## Track 1 — Infrastructure (Terragrunt)

### CI on every PR (`.github/workflows/ci.yml`)

Runs on pull requests and pushes to `main`. All gates are **enforcing** (a failure blocks the PR):

| Job | What it checks |
|-----|----------------|
| OpenTofu Format | `tofu fmt -check -recursive infra/modules/` |
| OpenTofu Validate | `tofu validate` per module (synthesizes a temporary `versions.tf` where absent) |
| Terragrunt HCL Format | `terragrunt hcl fmt --check` |
| Markdown Lint | `markdownlint-cli2` on changed `*.md` |
| TFLint | `tflint` per module (fails on `error` severity) |
| Kyverno Policy Test | renders the `policy` module's ClusterPolicies and runs `kyverno test` |
| Kyverno Shift-Left (dogfood) | runs the `kyverno-validate` composite action against committed compliant/broken sample apps — proves the app-repo gate works |
| Trivy (IaC + deps) | `trivy config infra/modules` + Go SCA on `infra/tests/aws`; blocks on HIGH/CRITICAL (ADR-014 Audit→Enforce; accepted findings in `.trivyignore.yaml`) |
| Semgrep (SAST) | `p/terraform`, `p/github-actions`, `p/secrets`, `p/golang`, `p/dockerfile` |

Security scanners are installed at **pinned, SHA-256-verified** versions (the
`aquasecurity/trivy-action` was compromised in 03/2026 — #112); findings surface in job logs +
SARIF artifacts (these repos are private without GitHub Advanced Security, so the Security tab is
unavailable).

### Module tests (`.github/workflows/test-aws.yml`)

Terratest (Go) for the heavyweight AWS modules (networking, EKS) runs **weekly** (Mon 06:00 UTC) and
on `workflow_dispatch`, assuming `TEST_ROLE_ARN` in the **test** sandbox account via GitHub OIDC
(`id-token: write`). See [Testing Strategy](15-testing-strategy.md).

### Apply (human-gated, not in CI)

There is **no auto-apply on merge** for infrastructure. Applies are run deliberately against a target
environment after reviewing the plan:

```bash
# From any live unit directory; provider assumes PlatformDeployer (root.hcl)
terragrunt plan        # review
terragrunt apply

# Or run the whole DAG for an environment
terragrunt run --all apply
```

`platctl` (ADR-038) wraps full-environment bring-up/teardown with dependency ordering and dry-run:

```bash
platctl bootstrap --dry-run
platctl bootstrap
platctl teardown
platctl validate            # post-apply health checks
```

Deployment ordering (Cilium-before-nodes, eks-addons after CNI, etc.) is documented in
[AGENTS.md](../../AGENTS.md#deployment-ordering--applydestroy-aws). State is per-unit in S3; the apply role chain is
described in [Security Architecture](09-security-architecture.md).

### Promotion

Module sources are pinned to the monorepo via `_versions.hcl`, so every environment runs the same
module code; promotion is a separate apply against each environment directory (see
[Environment Management](05-environment-management.md#promotion-workflow)).

## Track 2 — Application workloads (GitOps via ArgoCD)

Application repos own a `Dockerfile` + `k8s/` manifests; the platform provides ECR, the per-team push
role, ArgoCD, and the admission policy. The reference app is `app-alpha`.

### App-repo PR CI

| Workflow | Purpose |
|----------|---------|
| `validate.yml` | **Kyverno shift-left** — calls the platform's `kyverno-validate` composite action (`asanexample/platform/.github/actions/kyverno-validate@main`) to render environment policies and check `k8s/` manifests, failing the PR with the same checks admission enforces |
| `security.yml` | Trivy (Go SCA + Dockerfile config) + Semgrep, pinned/verified, blocking on HIGH/CRITICAL |
| `preview.yml` | On PR: builds + signs an image and drives an **ephemeral preview environment** (ArgoCD ApplicationSet PR generator; HTTPRoute hostnames patched per-PR) |

### Deploy on merge to `main` (`deploy.yml`)

1. **Build & push** the image to the platform ECR, authenticating with the per-team
   `github-actions-ecr-push-<team>` IAM role via GitHub OIDC (no static keys).
2. **Sign** the image **by digest** with **cosign keyless** (GitHub OIDC → Fulcio/Rekor).
3. **SBOM**: Syft generates a CycloneDX SBOM; cosign attaches it as a signed attestation.
4. **Provenance**: **SLSA Build L3** provenance is produced by the isolated
   `asanexample/trusted-ci` reusable workflow — the **sole** provenance signer, an identity the
   app's own build job cannot forge (ADR-042, #131).
5. **Pin & commit**: the `deploy` job (gated on *both* build and provenance) rewrites
   `k8s/preprod/deployment.yaml` to the signed digest and commits to `main`.
6. **ArgoCD syncs** the cluster to the new commit. At admission, Kyverno (Enforce) verifies the
   image signature (`verify-images-<team>-<product>`) and the SBOM + provenance attestations
   (`verify-attestations-<team>-<product>`) — see [Security Architecture](09-security-architecture.md).

Gating the commit on provenance is deliberate: it guarantees ArgoCD never sees a digest whose
attestation does not yet exist (which Enforce would reject).

```text
PR ──► validate.yml + security.yml (shift-left gates)
merge ─► build+push ─► cosign sign ─► SBOM attest ─► SLSA L3 provenance (trusted-ci)
                                                          │
                                          pin digest in k8s/ + commit
                                                          │
                                                  ArgoCD sync ─► Kyverno verify ─► running
```

## Next Steps

Continue to [Testing Strategy](15-testing-strategy.md) to understand how infrastructure is tested
throughout the deployment lifecycle.
