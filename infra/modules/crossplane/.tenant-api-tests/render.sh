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
[ "$n" -eq 11 ] || { echo "::error::expected 11 composed K8s Objects, got $n"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: alpha-demo-dev$'              || { echo "::error::namespace alpha-demo-dev not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/tenant: alpha' || { echo "::error::tenant label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/environment: dev' || { echo "::error::environment label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: alpha-demo-dev:developers'    || { echo "::error::developer RoleBinding group wrong"; exit 1; }
# per-app identity: app 'demo' (SA app-alpha) → its own Pod role Pod-<team>-<name>-<env>-<app>; no RolePolicy
printf '%s' "$OUT" | grep -q 'external-name: Pod-alpha-demo-dev-demo' || { echo "::error::per-app role Pod-alpha-demo-dev-demo not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'serviceAccount: app-alpha'          || { echo "::error::Pod Identity association SA wrong"; exit 1; }
rp=$(printf '%s' "$OUT" | grep -c 'kind: RolePolicy' || true); [ "$rp" -eq 0 ] || { echo "::error::alpha app has no permissions → expected 0 RolePolicy, got $rp"; exit 1; }
# ECR (team-scoped, env-agnostic): team-alpha/demo repo + cross-account pull policy
printf '%s' "$OUT" | grep -q 'external-name: team-alpha/demo' || { echo "::error::ECR repo team-alpha/demo not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'kind: RepositoryPolicy'         || { echo "::error::ECR RepositoryPolicy not rendered"; exit 1; }
# restrict-images (per-namespace name; image prefix is team-<team>, NOT the namespace — ECR is team-scoped)
printf '%s' "$OUT" | grep -q 'name: restrict-images-alpha-demo-dev'           || { echo "::error::restrict-images policy not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'image: .*/team-alpha/\*'                        || { echo "::error::restrict-images allowed prefix should be team-alpha (not the namespace)"; exit 1; }
# Route hostnames (ADR-060/061): per-namespace policy + generated host <app>-<team>-<env>; no spec.domains, so
# the allow-list is just the generated host (+ -pr-* wildcard) and status.domains = it Active.
printf '%s' "$OUT" | grep -q 'name: restrict-route-hostnames-alpha-demo-dev' || { echo "::error::restrict-route-hostnames policy not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'demo-alpha-dev.preprod.aws.refplat.org'        || { echo "::error::generated host demo-alpha-dev not in the allow-list"; exit 1; }
printf '%s' "$OUT" | grep -q 'reason: GeneratedHost'                         || { echo "::error::status.domains GeneratedHost entry missing"; exit 1; }
# ECR is retained on tenant delete (ADR-062 #283): the Repository + its policy carry deletionPolicy: Orphan so
# removing a claim never destroys the team-scoped/shared images. Two Orphans (Repository + RepositoryPolicy).
op=$(printf '%s' "$OUT" | grep -c 'deletionPolicy: Orphan' || true); [ "$op" -ge 2 ] || { echo "::error::ECR Repository/RepositoryPolicy must be deletionPolicy: Orphan (got $op)"; exit 1; }
echo "  ✓ alpha OK (11 K8s Objects, ns alpha-demo-dev, role Pod-alpha-demo-dev-demo, ECR team-alpha/demo Orphan, restrict-images + route-hostname guards)"

echo "== render decommissioning (lifecycle.phase) → reversible suspend: ResourceQuota zeroed, footprint retained =="
OUT="$(render "${here}/claims/decommissioning.yaml")"
printf '%s' "$OUT" | grep -q 'pods: "0"'         || { echo "::error::decommissioning must zero the ResourceQuota pods"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'requests.cpu: "0"' || { echo "::error::decommissioning must zero requests.cpu"; exit 1; }
# Everything else is RETAINED (reversible) — namespace, the minted role, ECR all still render.
printf '%s' "$OUT" | grep -q 'name: alpha-demo-dev$'                 || { echo "::error::decommissioning must retain the namespace"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: Pod-alpha-demo-dev-demo' || { echo "::error::decommissioning must retain the per-app role"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: team-alpha/demo'         || { echo "::error::decommissioning must retain the ECR repo"; exit 1; }
echo "  ✓ decommissioning OK (quota zeroed, namespace + role + ECR retained — reversible)"

echo "== render canonical (pci/dedicated, app api w/ permissions) → per-app identity + RolePolicy =="
OUT="$(render "${here}/claims/canonical.yaml")"
printf '%s' "$OUT" | grep -q 'name: payments-payments-api-prod$' || { echo "::error::canonical namespace wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/tier: pci' || { echo "::error::tier label wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: Pod-payments-payments-api-prod-api' || { echo "::error::per-app role for canonical not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'serviceAccount: payments-api'    || { echo "::error::canonical association SA wrong"; exit 1; }
printf '%s' "$OUT" | grep -q 's3:GetObject'                    || { echo "::error::canonical per-app RolePolicy missing the granted action"; exit 1; }
printf '%s' "$OUT" | grep -q 'ReadCustomerBucket'              || { echo "::error::canonical per-app RolePolicy Sid missing"; exit 1; }
# The deny-escalation permissions boundary (ADR-062 §4, #282) must be attached to every minted role — the hard
# runtime ceiling behind the policyStatements deny-set. Sourced from EnvironmentConfig.permissionsBoundaryArn.
printf '%s' "$OUT" | grep -q 'permissionsBoundary: arn:aws:iam::111122223333:policy/tenant-boundary' || { echo "::error::minted role missing the permissions boundary"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: team-payments/api' || { echo "::error::ECR repo team-payments/api not rendered"; exit 1; }
# External custom domain (not under our wildcard) → status.domains Pending (NOT admitted); the generated host
# api-payments-prod.preprod.aws.refplat.org stays Active.
printf '%s' "$OUT" | grep -q 'host: bigbank.payments.example.com' || { echo "::error::external domain not in status.domains"; exit 1; }
printf '%s' "$OUT" | grep -q 'reason: AwaitingProvisioning'       || { echo "::error::external domain should be Pending/AwaitingProvisioning"; exit 1; }
echo "  ✓ canonical OK (namespace payments-payments-api-prod, tier pci, per-app role + RolePolicy, ECR team-payments/api, external domain Pending)"

echo "v2 Composition render checks passed (A3c — K8s footprint + per-app AWS identity + ECR)."

# ===========================================================================================================
# v3 Environment Composition (ADR-067 / L2a #383) — ADDITIVE alongside v2. Renders v1alpha3 XEnvironment claims
# (.tenant-api-tests/environments/) against composition-v3.yaml: product-scoped ECR/identity + the v3 footprint.
# ===========================================================================================================
compv3="${here}/../charts/tenant/files/composition-v3.yaml"
renderv3() { crossplane render "$1" "$compv3" "$fns" --extra-resources "$envcfg" 2>/dev/null; }

echo "== render v3 demo-dev (first-deploy: web service, no image) → footprint + product-scoped ECR/identity =="
OUT="$(renderv3 "${here}/environments/demo-dev.yaml")"
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
OUT="$(renderv3 "${here}/environments/shop-bigbank-prod.yaml")"
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
