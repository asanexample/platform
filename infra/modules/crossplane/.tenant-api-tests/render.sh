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

echo "== render alpha (v1alpha2) → K8s footprint + per-app identity (no permissions) =="
OUT="$(render "${here}/claims/alpha.yaml")"
n=$(printf '%s' "$OUT" | grep -c 'kind: Object')
[ "$n" -eq 9 ] || { echo "::error::expected 9 composed K8s Objects, got $n"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: alpha-demo$'                  || { echo "::error::namespace alpha-demo not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/tenant: alpha' || { echo "::error::tenant label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/environment: preprod' || { echo "::error::environment label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: alpha-demo:developers'        || { echo "::error::developer RoleBinding group wrong"; exit 1; }
# per-app identity: app 'demo' (SA app-alpha) → its own Pod role + association; no RolePolicy (no permissions)
printf '%s' "$OUT" | grep -q 'external-name: Pod-alpha-demo-demo' || { echo "::error::per-app role Pod-alpha-demo-demo not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'serviceAccount: app-alpha'          || { echo "::error::Pod Identity association SA wrong"; exit 1; }
rp=$(printf '%s' "$OUT" | grep -c 'kind: RolePolicy' || true); [ "$rp" -eq 0 ] || { echo "::error::alpha app has no permissions → expected 0 RolePolicy, got $rp"; exit 1; }
echo "  ✓ alpha OK (9 K8s Objects, namespace alpha-demo, per-app role Pod-alpha-demo-demo, 0 RolePolicy)"

echo "== render canonical (pci/dedicated, app api w/ permissions) → per-app identity + RolePolicy =="
OUT="$(render "${here}/claims/canonical.yaml")"
printf '%s' "$OUT" | grep -q 'name: payments-payments-api$' || { echo "::error::canonical namespace wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/tier: pci' || { echo "::error::tier label wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: Pod-payments-payments-api-api' || { echo "::error::per-app role for canonical not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'serviceAccount: payments-api'    || { echo "::error::canonical association SA wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 's3:GetObject'                    || { echo "::error::canonical per-app RolePolicy missing the granted action"; exit 1; }
printf '%s' "$OUT" | grep -q 'ReadCustomerBucket'              || { echo "::error::canonical per-app RolePolicy Sid missing"; exit 1; }
echo "  ✓ canonical OK (namespace payments-payments-api, tier pci, per-app role + RolePolicy)"

echo "v2 Composition render checks passed (A3b — K8s footprint + per-app AWS identity)."
