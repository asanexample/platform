#!/usr/bin/env bash
# Offline schema-validation harness for the Tenant API (XRD). Validates the example claims against the XRD's
# OpenAPI v3 schema + CEL rules with `crossplane beta validate` — no cluster, no Composition (that's the v2
# Composition, delivery-plan A3). Driven in CI by the "Tenant API Schema" job; runnable locally if you have
# the crossplane CLI. See docs/architecture/tenant-api-v2.md and docs/plans/tenant-api-v2-and-identity-delivery.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
charts="${here}/../charts/tenant/templates"
xrd="${charts}/xrd.yaml"             # XTenant XRD (the Tenant claim)
team_crd="${charts}/team-crd.yaml"   # projected Team CRD (the envelope)

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

if [ "$fail" -ne 0 ]; then
  echo "Tenant API schema validation FAILED"
  exit 1
fi
echo "Tenant API schema validation OK"
