#!/usr/bin/env bash
# Offline schema-validation harness for the ServiceGrant API (ADR-101). Validates the example claims against
# the v1beta1 OpenAPI schema with `crossplane beta validate` — no cluster, no Composition (that's render.sh).
# Mirrors .environment-api-tests/run.sh's validate_dir pattern.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xrd="${here}/../charts/service-grant-api/templates/xservicegrant-xrd.yaml"

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

validate_dir "$xrd" "valid ServiceGrant claims"   "${here}/service-grants"         pass
validate_dir "$xrd" "invalid ServiceGrant claims" "${here}/service-grants-invalid" reject

# Live git-native objects (gitops/grants/**) — crossplane beta validate recurses per-team subdirs. Harmless
# no-op today (no ServiceGrant authored yet — Part 6 is a separate deliverable); a mixed AccessGrant/
# ServiceGrant directory is fine because beta validate only flags resources matching THIS schema's kind.
if [ -d "${repo_root}/gitops/grants" ]; then
  validate_dir "$xrd" "live ServiceGrant objects (gitops/grants)" "${repo_root}/gitops/grants" pass
fi

if [ "$fail" -ne 0 ]; then
  echo "ServiceGrant API schema validation FAILED"
  exit 1
fi
echo "ServiceGrant API schema validation OK"
