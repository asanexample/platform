#!/usr/bin/env bash
# Offline schema-validation harness for the Tenant API (XRD). Validates the example claims against the XRD's
# OpenAPI v3 schema + CEL rules with `crossplane beta validate` — no cluster, no Composition (that's the v2
# Composition, delivery-plan A3). Driven in CI by the "Tenant API Schema" job; runnable locally if you have
# the crossplane CLI. See docs/architecture/tenant-api-v2.md and docs/plans/tenant-api-v2-and-identity-delivery.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
charts="${here}/../charts/tenant/templates"
xrd="${charts}/xrd.yaml"                       # XTenant XRD (v2, the live Tenant claim)
team_crd="${charts}/team-crd.yaml"             # projected Team CRD (v1alpha2 storage + v1alpha3 served)
# v3 (ADR-067) — added ADDITIVELY alongside v2 (the cutover removes v2 in a future cycle).
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

# Tenant claims (XTenant XRD)
validate_dir "$xrd" "valid Tenant claims"   "${here}/claims"  pass
validate_dir "$xrd" "invalid Tenant claims" "${here}/invalid" reject

# Projected Team records (Team CRD)
validate_dir "$team_crd" "valid Team records"   "${here}/teams"         pass
validate_dir "$team_crd" "invalid Team records" "${here}/teams-invalid" reject

# Live git-native Team objects (gitops/teams/ — what ArgoCD actually syncs). Gives Team-onboarding PRs
# (the Backstage New Team template, #280) a real schema gate in CI, not just human review.
repo_root="$(cd "${here}/../../../.." && pwd)"
validate_dir "$team_crd" "live Team objects (gitops/teams)" "${repo_root}/gitops/teams" pass

# ===========================================================================================================
# v3 API (ADR-067) — XEnvironment + Product + AccessGrant + the v1alpha3 Team envelope. Added ADDITIVELY: the
# v2 surface above is unchanged and still validated; the v2→v3 cutover (removing v2) is a future cycle.
# ===========================================================================================================
validate_dir "$xenv_xrd"    "valid Environment claims (v3)"   "${here}/environments"          pass
validate_dir "$xenv_xrd"    "invalid Environment claims (v3)" "${here}/environments-invalid"  reject
validate_dir "$product_crd" "valid Product records (v3)"      "${here}/products"              pass
validate_dir "$product_crd" "invalid Product records (v3)"    "${here}/products-invalid"      reject
validate_dir "$grant_crd"   "valid AccessGrant records (v3)"  "${here}/grants"                pass
validate_dir "$grant_crd"   "invalid AccessGrant records (v3)" "${here}/grants-invalid"       reject
validate_dir "$team_crd"    "valid Team records (v1alpha3)"   "${here}/teams-v3"              pass
validate_dir "$team_crd"    "invalid Team records (v1alpha3)" "${here}/teams-v3-invalid"     reject

# Live v3 git-native objects (the new gitops layout). crossplane beta validate recurses the per-team subdirs.
validate_dir "$product_crd" "live Product objects (gitops/products)"          "${repo_root}/gitops/products"     pass
validate_dir "$xenv_xrd"    "live Environment objects (gitops/environments)"  "${repo_root}/gitops/environments" pass

# Registry → projection (the crossplane-teams chart, delivery-plan A2). Render the canonical registry into
# projected Team CRs and (a) validate them against the Team CRD, (b) assert the canonical-only fields are
# dropped. Needs helm; skip gracefully if absent (the CI job installs it).
if command -v helm >/dev/null 2>&1; then
  echo "== Team registry projection (crossplane-teams chart) =="
  proj="${here}/rendered-teams.yaml"
  helm template teams "${here}/../charts/teams" -f "${here}/registry-values.yaml" > "$proj"
  if ! crossplane beta validate "$team_crd" "$proj"; then
    echo "::error::projected Team CRs failed validation against the Team CRD"
    fail=1
  fi
  for t in payments alpha bravo; do
    grep -q "name: ${t}$" "$proj" || { echo "::error::projection missing Team '${t}'"; fail=1; }
  done
  # canonical-only fields must NOT leak into the projected CRs
  for leaked in displayName developerGroup costCenter contacts; do
    if grep -q "${leaked}" "$proj"; then echo "::error::projection leaked canonical-only field '${leaked}'"; fail=1; fi
  done
  rm -f "$proj"
  echo
else
  echo "(helm not found — skipping projection render check)"
  echo
fi

if [ "$fail" -ne 0 ]; then
  echo "Tenant API schema validation FAILED"
  exit 1
fi
echo "Tenant API schema validation OK"
