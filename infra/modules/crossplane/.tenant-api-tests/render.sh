#!/usr/bin/env bash
# Offline `crossplane render` test for the v2 Tenant Composition (delivery-plan A3). Runs the Pipeline
# functions via Docker and asserts the rendered tenant footprint — no cluster. Heavier than the schema check
# (Docker + function image pulls), so it runs as its own CI job ("Tenant Composition Render"), not in run.sh.
# Requires crossplane + docker. See docs/architecture/tenant-api-v2.md.
#
# A3a scope: the Kubernetes footprint (namespace <team>-<name>, quota, limits, NetworkPolicies,
# CiliumNetworkPolicies, developer RoleBinding). AWS per-app identity (A3b) + ECR (A3c) extend it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
comp="${here}/../charts/tenant/files/composition-v2.yaml"
fns="${here}/render/functions.yaml"
envcfg="${here}/render/environmentconfig.yaml"

command -v crossplane >/dev/null 2>&1 || { echo "::error::crossplane CLI not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "::error::docker is required for crossplane render"; exit 1; }

render() { crossplane render "$1" "$comp" "$fns" --extra-resources "$envcfg" 2>/dev/null; }

echo "== render alpha (v1alpha2) → namespace alpha-demo, full K8s footprint =="
OUT="$(render "${here}/claims/alpha.yaml")"
n=$(printf '%s' "$OUT" | grep -c 'kind: Object')
[ "$n" -eq 9 ] || { echo "::error::expected 9 composed Objects, got $n"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: alpha-demo$'                  || { echo "::error::namespace alpha-demo not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/tenant: alpha' || { echo "::error::tenant label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/environment: preprod' || { echo "::error::environment label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: alpha-demo:developers'        || { echo "::error::developer RoleBinding group wrong"; exit 1; }
echo "  ✓ alpha footprint OK (9 Objects, namespace alpha-demo)"

echo "== render canonical (pci/dedicated) → namespace payments-payments-api =="
OUT="$(render "${here}/claims/canonical.yaml")"
printf '%s' "$OUT" | grep -q 'name: payments-payments-api$' || { echo "::error::canonical namespace wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/tier: pci' || { echo "::error::tier label wrong"; exit 1; }
echo "  ✓ canonical footprint OK (namespace payments-payments-api, tier pci)"

echo "v2 Composition render checks passed (A3a — Kubernetes footprint)."
