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
echo "  ✓ alpha OK (11 K8s Objects, ns alpha-demo-dev, role Pod-alpha-demo-dev-demo, ECR team-alpha/demo, restrict-images + route-hostname guards)"

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
