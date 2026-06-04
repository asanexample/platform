#!/usr/bin/env bash
# Offline schema-validation harness for the Tenant API (XRD). Validates the example claims against the XRD's
# OpenAPI v3 schema + CEL rules with `crossplane beta validate` — no cluster, no Composition (that's the v2
# Composition, delivery-plan A3). Driven in CI by the "Tenant API Schema" job; runnable locally if you have
# the crossplane CLI. See docs/architecture/tenant-api-v2.md and docs/plans/tenant-api-v2-and-identity-delivery.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xrd="${here}/../charts/tenant/templates/xrd.yaml"
valid_dir="${here}/claims"
invalid_dir="${here}/invalid"

command -v crossplane >/dev/null 2>&1 || { echo "::error::crossplane CLI not found on PATH"; exit 1; }

fail=0

echo "== valid claims (must all pass) =="
if ! crossplane beta validate "$xrd" "$valid_dir"; then
  echo "::error::a claim under claims/ failed validation but is expected to pass"
  fail=1
fi

echo
echo "== invalid claims (each must be rejected) =="
for f in "$invalid_dir"/*.yaml; do
  name="$(basename "$f")"
  if crossplane beta validate "$xrd" "$f" >/dev/null 2>&1; then
    echo "::error::invalid/${name} PASSED validation but must be rejected"
    fail=1
  else
    echo "  ✓ correctly rejected: ${name}"
  fi
done

echo
if [ "$fail" -ne 0 ]; then
  echo "Tenant API schema validation FAILED"
  exit 1
fi
echo "Tenant API schema validation OK"
