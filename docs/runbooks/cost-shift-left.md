# Runbook: Shift-left cost-in-PR (Infracost)

Surfaces the cost impact of an infrastructure change **in the pull request**, before apply — the platform-
engineer half of the FinOps shift-left (ADR-092 D5/D6, #1056). Uses the **free** Infracost CLI + pricing API,
self-hosted in CI (not the paid Infracost Cloud).

- **Workflow:** `.github/workflows/infracost.yml` (runs on PRs touching `infra/modules/**`)

## One-time prerequisite: the API key (free)

Infracost needs a free pricing-API key (no credit card):

1. Get a key: `infracost auth login` locally, or sign up at <https://www.infracost.io/docs/#2-get-api-key>.
2. Add it as a **repository secret** named `INFRACOST_API_KEY` (Settings → Secrets and variables → Actions).

Until the secret is set, the workflow is a **clean no-op** — it prints a notice and passes, it does **not** fail
the PR.

## Scope (and why)

The workflow prices the shared **modules** under `infra/modules/`, not the live Terragrunt units. Infracost's
own Terragrunt HCL evaluator can't parse this repo's unit config hierarchy (the `env.hcl` conditional + the
SOPS-decrypted secrets in `common.hcl`), so units aren't priced. That's an acceptable v1: the cost-bearing
resources (NAT gateways, EKS, node groups, instances, TGW, ...) are **defined in the modules**, which Infracost
prices fine and credential-free. A PR that changes a module's cost-bearing resources gets a cost-diff comment.

**Follow-up (#1056):** unit-level precision (real per-environment sizing) would need the Terragrunt-eval
incompatibility resolved + a read-only CI role for `terraform plan` JSON. Deferred.

## What you'll see

On a PR that changes a module, Infracost posts/updates a single comment with the monthly-cost diff (e.g.
`infra/modules/aws/eks  +$74`). No comment means no module cost change. Baseline reference (current main):
`aws/eks ≈ $74/mo`, `aws/transit-gateway ≈ $36.50/mo`, `aws/ssm-bastion ≈ $4.60/mo` — usage-based resources
(S3, Athena, SNS) show `$0` baseline + a usage note.

## Cost

Free — the Infracost CLI and pricing API are free, and we don't use Infracost Cloud (the paid dashboards tier).
