#!/usr/bin/env bash
#
# Reconcile the per-Product Terragrunt-derived units after a gitops/products/** change merges (ADR-071 Gap #2,
# the New Product self-service seam). Three units derive their per-Product resources from the Product registry
# (gitops/products/<team>/<product>.yaml) via fileset+yamldecode — so a brand-new Product has NONE of them until
# they're applied, and its first build/deploy fails (no OIDC push-role → sts:AssumeRoleWithWebIdentity denied; no
# ApplicationSet → no delivery; no verify-images-product → unsigned). This closes the seam: on every
# gitops/products merge, converge them with zero operator action, always from the merged SHA.
#
#   platform/github-oidc   per-Product ECR-push role (+ the promote-secret read, ADR-071 PR3)
#   preprod/policy         per-Product verify-images-product cosign gate (ADR-046)
#   platform/argocd-apps   per-Product ApplicationSet (ADR-069 delivery)
#   platform/github-teams  per-Product org-Team `push` grant on the <team>-<product> repo (ADR-072 ownership)
#
# Each is conditional (plan -detailed-exitcode → apply only on a diff) + idempotent. The GitOps/Crossplane half
# (namespace/ECR/Pod-Identity from the Composition) already auto-provisions via ArgoCD — only these Terragrunt
# units need the apply.
#
# Env: GITHUB_STEP_SUMMARY (Actions-provided). Run on the in-VPC platform-infra runner (Pod Identity →
# TG_FORCE_DEPLOYER assumes PlatformDeployer + TerraformStateAccess).
set -uo pipefail
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
PLATFORM="infra/live/aws/platform/us-east-1/platform"
PREPROD="infra/live/aws/preprod/us-east-1/platform"

echo "## Registry reconcile — per-Product units (ADR-071 Gap #2)" >> "$SUMMARY"

# run <unit-dir>  — conditional apply (no-op when there's no diff), output → the job summary.
run() {
  local dir="$1" raw rc status
  raw="$(mktemp)"
  echo "::group::terragrunt reconcile — ${dir}"
  rc=0
  (cd "$dir" && terragrunt plan -detailed-exitcode -no-color -input=false) > "$raw" 2>&1 || rc=$?
  case "$rc" in
    0) status="no changes — skipped" ;;
    2) if (cd "$dir" && terragrunt apply -auto-approve -no-color -input=false) >> "$raw" 2>&1; then status="applied"; else status="APPLY FAILED"; fi ;;
    *) status="PLAN FAILED" ;;
  esac
  cat "$raw"
  echo "::endgroup::"
  {
    echo "<details><summary><code>${dir#infra/live/aws/}</code> — ${status}</summary>"
    echo
    echo '```text'
    tail -n 200 "$raw"
    echo '```'
    echo "</details>"
    echo
  } >> "$SUMMARY"
  rm -f "$raw"
  case "$status" in *FAILED*) return 1 ;; esac
  return 0
}

# Order: CI push-auth first, then the admission gate, then delivery — so a new Product can build, be admitted,
# and deploy. Independent units, but fail-fast in this logical order.
run "${PLATFORM}/github-oidc" || { echo "::error::github-oidc reconcile failed — stopping"; exit 1; }
run "${PREPROD}/policy"       || { echo "::error::preprod/policy reconcile failed — stopping"; exit 1; }
run "${PLATFORM}/argocd-apps" || { echo "::error::argocd-apps reconcile failed — stopping"; exit 1; }
# github-teams grants the owning team `push` on the new <team>-<product> repo (ADR-072 ownership layer). The
# team itself is created by teams-apply (on the Team CR); this is the per-Product repo grant. Conditional +
# idempotent across both workflows.
run "${PLATFORM}/github-teams" || { echo "::error::github-teams reconcile failed — stopping"; exit 1; }
echo "per-Product units converged"
