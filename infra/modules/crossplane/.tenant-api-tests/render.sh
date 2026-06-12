#!/usr/bin/env bash
# Offline `crossplane render` test for the v3 Environment Composition (ADR-067 / L2a #383). Runs the Pipeline
# functions via Docker and asserts the rendered Environment footprint — no cluster. Heavier than the schema
# check (Docker + function image pulls), so it runs as its own CI job ("Tenant Composition Render"), not in
# run.sh. Requires crossplane + docker. v3-only since the cutover (the v2 Composition was removed).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
comp="${here}/../charts/tenant/files/composition-v3.yaml"
fns="${here}/render/functions.yaml"
envcfg="${here}/render/environmentconfig.yaml"

command -v crossplane >/dev/null 2>&1 || { echo "::error::crossplane CLI not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "::error::docker is required for crossplane render"; exit 1; }

render() { crossplane render "$1" "$comp" "$fns" --extra-resources "$envcfg" 2>/dev/null; }

echo "== render v3 demo-dev (first-deploy: web service, no image) → footprint + product-scoped ECR/identity =="
OUT="$(render "${here}/environments/demo-dev.yaml")"
printf '%s' "$OUT" | grep -q 'name: alpha-demo-dev$'                  || { echo "::error::v3 namespace alpha-demo-dev not rendered"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/product: demo'     || { echo "::error::v3 product label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/stage: dev'        || { echo "::error::v3 stage label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: team-alpha/demo-web'     || { echo "::error::v3 product-scoped ECR team-alpha/demo-web not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: Pod-alpha-demo-dev-web'  || { echo "::error::v3 Pod role Pod-alpha-demo-dev-web not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: alpha-demo-dev:developers'        || { echo "::error::v3 developer RoleBinding group wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 'team-alpha/demo-\*'                     || { echo "::error::v3 restrict-images scope should be team-alpha/demo-*"; exit 1; }
printf '%s' "$OUT" | grep -q 'demo-alpha-dev.preprod.aws.refplat.org' || { echo "::error::v3 generated host demo-alpha-dev not in the allow-list"; exit 1; }
echo "  ✓ v3 demo-dev OK (ns alpha-demo-dev, ECR team-alpha/demo-web, role Pod-alpha-demo-dev-web, restrict-images team-alpha/demo-*)"

echo "== render v3 shop-bigbank-prod (per-customer pci prod, image + permissions) → customer-ns + RolePolicy =="
OUT="$(render "${here}/environments/shop-bigbank-prod.yaml")"
printf '%s' "$OUT" | grep -q 'name: alpha-shop-bigbank-prod$'        || { echo "::error::v3 per-customer namespace alpha-shop-bigbank-prod not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/customer: bigbank' || { echo "::error::v3 customer label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: team-alpha/shop-api'     || { echo "::error::v3 ECR team-alpha/shop-api not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: Pod-alpha-shop-prod-api' || { echo "::error::v3 Pod role Pod-alpha-shop-prod-api not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 's3:GetObject'                          || { echo "::error::v3 per-service RolePolicy missing the granted action"; exit 1; }
printf '%s' "$OUT" | grep -q 'permissionsBoundary'                   || { echo "::error::v3 minted role missing the permissions boundary"; exit 1; }
printf '%s' "$OUT" | grep -q 'host: shop.example.com'                || { echo "::error::v3 bound domain shop.example.com not in status.domains"; exit 1; }
printf '%s' "$OUT" | grep -q 'reason: BoundDomain'                   || { echo "::error::v3 bound domain should be reason BoundDomain"; exit 1; }
echo "  ✓ v3 shop-bigbank-prod OK (customer-ns, ECR team-alpha/shop-api, role + RolePolicy + boundary, bound domain Active)"

echo "v3 Environment Composition render checks passed (L2a — product-scoped footprint + identity)."
