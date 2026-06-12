#!/usr/bin/env bash
# Unit test for validate-deletions.sh — both guards (Environment decommission-first + Product-deletion
# completeness). Self-contained: builds throwaway BASE_DIR fixtures, runs the script with various DELETED_FILES,
# and asserts the exit code. Run locally: bash .github/scripts/v3-gate/test-validate-deletions.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/validate-deletions.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::yq required"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
base="${work}/base"

# Fixtures on the BASE branch:
#   - Product alpha/shop  : two Environments — dev (active), prod (decommissioning)
#   - Product alpha/lonely: no Environments
#   - Product alpha/done  : one Environment — staging (decommissioning), fully wound down
mkdir -p "${base}/gitops/products/alpha" \
         "${base}/gitops/environments/alpha/shop" "${base}/gitops/environments/alpha/done"
for p in shop lonely done; do
  cat >"${base}/gitops/products/alpha/${p}.yaml" <<Y
apiVersion: platform.refplat.org/v1alpha3
kind: Product
metadata: { name: alpha-${p} }
spec: { team: alpha, repo: asanexample/app-alpha-${p}, tenancy: pooled }
Y
done
cat >"${base}/gitops/environments/alpha/shop/dev.yaml"  <<'Y'
apiVersion: platform.refplat.org/v1alpha3
kind: XEnvironment
metadata: { name: alpha-shop-dev }
spec: { team: alpha, product: shop, stage: dev }
Y
cat >"${base}/gitops/environments/alpha/shop/prod.yaml" <<'Y'
apiVersion: platform.refplat.org/v1alpha3
kind: XEnvironment
metadata: { name: alpha-shop-prod }
spec: { team: alpha, product: shop, stage: prod, lifecycle: { phase: decommissioning } }
Y
cat >"${base}/gitops/environments/alpha/done/staging.yaml" <<'Y'
apiVersion: platform.refplat.org/v1alpha3
kind: XEnvironment
metadata: { name: alpha-done-staging }
spec: { team: alpha, product: done, stage: staging, lifecycle: { phase: decommissioning } }
Y

pass=0; failc=0
# run <expect: ok|deny> <name> <DELETED_FILES...>
run() {
  local expect="$1" name="$2"; shift 2
  BASE_DIR="$base" DELETED_FILES="$*" bash "$script" >/dev/null 2>&1
  local rc=$?
  local got=ok; [ $rc -ne 0 ] && got=deny
  if [ "$got" = "$expect" ]; then echo "  ✓ ${name} (${got})"; pass=$((pass+1))
  else echo "  ✗ ${name}: expected ${expect}, got ${got} (rc=${rc})"; failc=$((failc+1)); fi
}

echo "== validate-deletions.sh unit tests =="
# Guard 1 — Environment decommission-first
run deny "env delete, active on base"               "gitops/environments/alpha/shop/dev.yaml"
run ok   "env delete, decommissioning on base"      "gitops/environments/alpha/shop/prod.yaml"
# Guard 2 — Product-deletion completeness
run deny "product delete, Environments remain"      "gitops/products/alpha/shop.yaml"
run ok   "product delete, no Environments"          "gitops/products/alpha/lonely.yaml"
run ok   "product + its only (decommd) env same PR" "gitops/products/alpha/done.yaml gitops/environments/alpha/done/staging.yaml"
run deny "product + only SOME envs same PR"         "gitops/products/alpha/shop.yaml gitops/environments/alpha/shop/prod.yaml"
# The two guards compose: a same-PR teardown that includes an ACTIVE env is still denied by Guard 1 first.
run deny "product + an ACTIVE env same PR"          "gitops/products/alpha/shop.yaml gitops/environments/alpha/shop/dev.yaml gitops/environments/alpha/shop/prod.yaml"

echo "── ${pass} passed, ${failc} failed ──"
[ "$failc" -eq 0 ] || exit 1
