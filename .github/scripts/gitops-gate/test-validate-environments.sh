#!/usr/bin/env bash
# Unit test for validate-environments.sh — focuses on the ADR-073 self-service resource shift-left (engine ∈
# Team allowedEngines DEFAULT-DENY, count ≤ maxPerEnvironment, valid name/access/kind, isolation floor) plus a
# couple of baseline envelope checks. Self-contained: builds a throwaway checkout (Teams + Products + the
# Environment claim under test), runs the validator with ENVIRONMENT_FILES, asserts the exit code.
# Run: bash .github/scripts/gitops-gate/test-validate-environments.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/validate-environments.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::yq required"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
head="${work}/head"
mkdir -p "${head}/gitops/teams" "${head}/gitops/products/alpha" "${head}/gitops/products/bravo"

# Team alpha: opted in to S3, cap 2, pooled floor.
cat >"${head}/gitops/teams/alpha.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Team
metadata: { name: alpha }
spec:
  ssoGroup: Dev-alpha
  envelope:
    allowedTiers: ["standard"]
    allowedStages: ["dev", "test", "staging", "prod"]
    quotaCap: { cpu: "8", memory: 16Gi, pods: 40 }
    resources:
      allowedEngines: ["s3"]
      maxPerEnvironment: 2
      isolationFloor: shared
Y
# Team bravo: NO resources envelope → default-deny (may provision nothing).
cat >"${head}/gitops/teams/bravo.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Team
metadata: { name: bravo }
spec:
  ssoGroup: Dev-bravo
  envelope:
    allowedTiers: ["standard"]
    allowedStages: ["dev", "test", "staging", "prod"]
    quotaCap: { cpu: "8", memory: 16Gi, pods: 40 }
Y
cat >"${head}/gitops/products/alpha/shop.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: shop }
spec: { team: alpha, tenancy: pooled }
Y
cat >"${head}/gitops/products/bravo/widget.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: widget }
spec: { team: bravo, tenancy: pooled }
Y

pass=0; failc=0
# run <expect: ok|deny> <name> <env-rel-path> <body>
run() {
  local expect="$1" name="$2" relpath="$3" body="$4"
  mkdir -p "${head}/$(dirname "$relpath")"
  printf '%s\n' "$body" >"${head}/${relpath}"
  BASE_DIR="$head" HEAD_DIR="$head" ENVIRONMENT_FILES="$relpath" bash "$script" >/dev/null 2>&1
  local rc=$?; local got=ok; [ $rc -ne 0 ] && got=deny
  rm -f "${head}/${relpath}"
  if [ "$got" = "$expect" ]; then echo "  ✓ ${name} (${got})"; pass=$((pass+1));
  else echo "  ✗ ${name}: expected ${expect}, got ${got}"; failc=$((failc+1)); fi
}

echo "== validate-environments.sh (ADR-073 resources) =="
run ok   "baseline env, no resources" gitops/environments/alpha/shop/dev.yaml "$(cat <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: alpha-shop-dev }
spec: { team: alpha, product: shop, stage: dev, services: { web: { serviceAccount: shop-web } } }
Y
)"
run ok   "valid s3 resource (read+readwrite, within cap)" gitops/environments/alpha/shop/dev.yaml "$(cat <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: alpha-shop-dev }
spec:
  team: alpha
  product: shop
  stage: dev
  services:
    web:
      serviceAccount: shop-web
      resources:
        uploads: { kind: objectstore, engine: s3, access: readwrite }
        assets: { kind: objectstore, engine: s3, access: read }
Y
)"
run deny "engine not in Team allowedEngines (sqs)" gitops/environments/alpha/shop/dev.yaml "$(cat <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: alpha-shop-dev }
spec:
  team: alpha
  product: shop
  stage: dev
  services:
    web:
      serviceAccount: shop-web
      resources:
        q: { kind: stream, engine: sqs, access: readwrite }
Y
)"
run deny "exceeds maxPerEnvironment (3 > cap 2)" gitops/environments/alpha/shop/dev.yaml "$(cat <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: alpha-shop-dev }
spec:
  team: alpha
  product: shop
  stage: dev
  services:
    web:
      serviceAccount: shop-web
      resources:
        a: { kind: objectstore, engine: s3, access: read }
        b: { kind: objectstore, engine: s3, access: read }
        c: { kind: objectstore, engine: s3, access: read }
Y
)"
run deny "invalid access value" gitops/environments/alpha/shop/dev.yaml "$(cat <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: alpha-shop-dev }
spec:
  team: alpha
  product: shop
  stage: dev
  services:
    web:
      serviceAccount: shop-web
      resources:
        uploads: { kind: objectstore, engine: s3, access: admin }
Y
)"
run deny "invalid resource name (uppercase)" gitops/environments/alpha/shop/dev.yaml "$(cat <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: alpha-shop-dev }
spec:
  team: alpha
  product: shop
  stage: dev
  services:
    web:
      serviceAccount: shop-web
      resources:
        Uploads: { kind: objectstore, engine: s3, access: read }
Y
)"
run deny "default-deny: Team with no resources envelope" gitops/environments/bravo/widget/dev.yaml "$(cat <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: bravo-widget-dev }
spec:
  team: bravo
  product: widget
  stage: dev
  services:
    web:
      serviceAccount: widget-web
      resources:
        uploads: { kind: objectstore, engine: s3, access: read }
Y
)"
run ok   "Team with no resources envelope, no resources declared" gitops/environments/bravo/widget/dev.yaml "$(cat <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: bravo-widget-dev }
spec: { team: bravo, product: widget, stage: dev, services: { web: { serviceAccount: widget-web } } }
Y
)"

echo "${pass} passed, ${failc} failed"
[ "$failc" -eq 0 ]
