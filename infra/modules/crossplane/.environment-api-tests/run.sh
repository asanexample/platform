#!/usr/bin/env bash
# Offline schema-validation harness for the Environment API (ADR-067). Validates the example claims/records
# against each XRD/CRD's OpenAPI v3 schema + CEL rules with `crossplane beta validate` — no cluster, no
# Composition (that's render.sh). Driven in CI by the "Environment API Schema" job; runnable locally with the
# crossplane CLI. v3-only since the cutover (the v1alpha2 XTenant surface was removed).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
charts="${here}/../charts/environment-api/templates"
team_crd="${charts}/team-crd.yaml"             # projected Team CRD (v1alpha3)
xenv_xrd="${charts}/xenvironment-xrd.yaml"     # XEnvironment XRD (v3, the Environment claim)
product_crd="${charts}/product-crd.yaml"       # projected Product CRD (delivery identity)
grant_crd="${charts}/access-grant-crd.yaml"    # projected AccessGrant CRD (ADR-068)

command -v crossplane >/dev/null 2>&1 || { echo "::error::crossplane CLI not found on PATH"; exit 1; }

fail=0

# validate_dir <schema-file> <label> <dir> <expect: pass|reject>
validate_dir() {
  local schema="$1" label="$2" dir="$3" expect="$4"
  if [ "$expect" = "pass" ]; then
    echo "== ${label} (must all pass) =="
    if ! crossplane beta validate "$schema" "$dir"; then
      echo "::error::a resource under $(basename "$dir")/ failed validation but is expected to pass"
      fail=1
    fi
  else
    echo "== ${label} (each must be rejected) =="
    local f name
    for f in "$dir"/*.yaml; do
      name="$(basename "$f")"
      if crossplane beta validate "$schema" "$f" >/dev/null 2>&1; then
        echo "::error::$(basename "$dir")/${name} PASSED validation but must be rejected"
        fail=1
      else
        echo "  ✓ correctly rejected: ${name}"
      fi
    done
  fi
  echo
}

repo_root="$(cd "${here}/../../../.." && pwd)"

# ===========================================================================================================
# v3 API (ADR-067) — XEnvironment + Product + AccessGrant + the v1alpha3 Team envelope.
# ===========================================================================================================
# Projected Team records (Team CRD, v1alpha3)
validate_dir "$team_crd"    "valid Team records (v1alpha3)"   "${here}/teams-v3"              pass
validate_dir "$team_crd"    "invalid Team records (v1alpha3)" "${here}/teams-v3-invalid"     reject
# Live git-native Team objects (gitops/teams/ — what ArgoCD actually syncs). Gives Team-onboarding PRs a real
# schema gate in CI, not just human review.
validate_dir "$team_crd"    "live Team objects (gitops/teams)" "${repo_root}/gitops/teams"   pass

validate_dir "$xenv_xrd"    "valid Environment claims (v3)"   "${here}/environments"          pass
validate_dir "$xenv_xrd"    "invalid Environment claims (v3)" "${here}/environments-invalid"  reject
validate_dir "$product_crd" "valid Product records (v3)"      "${here}/products"              pass
validate_dir "$product_crd" "invalid Product records (v3)"    "${here}/products-invalid"      reject
validate_dir "$grant_crd"   "valid AccessGrant records (v3)"  "${here}/grants"                pass
validate_dir "$grant_crd"   "invalid AccessGrant records (v3)" "${here}/grants-invalid"       reject

# Live v3 git-native objects (the new gitops layout). crossplane beta validate recurses the per-team subdirs.
validate_dir "$product_crd" "live Product objects (gitops/products)"          "${repo_root}/gitops/products"     pass
validate_dir "$xenv_xrd"    "live Environment objects (gitops/environments)"  "${repo_root}/gitops/environments" pass

if [ "$fail" -ne 0 ]; then
  echo "Environment API schema validation FAILED"
  exit 1
fi
echo "Environment API schema validation OK"
