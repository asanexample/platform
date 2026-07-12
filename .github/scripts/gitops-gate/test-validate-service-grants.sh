#!/usr/bin/env bash
# Unit test for validate-service-grants.sh (ADR-101) — cluster-free, runs in CI alongside the other gitops-gate
# tests. Builds tiny ServiceGrant + Product + Environment fixtures in a temp tree and asserts the validator's
# verdicts. Requires yq (mikefarah).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$HERE/validate-service-grants.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/gitops/grants/bravo" "$T/gitops/grants/alpha" "$T/gitops/products/bravo" "$T/gitops/products/alpha" "$T/gitops/environments/bravo/dispatch" "$T/gitops/environments/alpha/shop"

cat > "$T/gitops/products/bravo/dispatch.yaml" <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: bravo-dispatch }
spec: { team: bravo, repo: asanexample/bravo-dispatch }
EOF

cat > "$T/gitops/products/alpha/shop.yaml" <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-shop }
spec: { team: alpha, repo: asanexample/alpha-shop }
EOF

cat > "$T/gitops/environments/bravo/dispatch/dev.yaml" <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: dispatch-dev }
spec: { team: bravo, product: dispatch, stage: dev, tier: standard }
EOF

cat > "$T/gitops/environments/alpha/shop/dev.yaml" <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: shop-dev }
spec: { team: alpha, product: shop, stage: dev, tier: standard }
EOF

cat > "$T/gitops/environments/bravo/dispatch/prod.yaml" <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: dispatch-prod }
spec: { team: bravo, product: dispatch, stage: prod, tier: hipaa }
EOF

mk() { cat > "$T/gitops/grants/$1"; }
run() { BASE_DIR="$T" HEAD_DIR="$T" GRANT_FILES="gitops/grants/$1" bash "$VALIDATOR" 2>/dev/null; }

fail=0
ok()  { echo "  ✓ $1"; }
bad() { echo "::error::test-validate-service-grants: $1" >&2; fail=1; }

# 1. a clean, valid grant in the CORRECT (target.team) directory → pass
mk bravo/good.yaml <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: ServiceGrant
metadata: { name: allow-shop-to-intake }
spec:
  target: { team: bravo, product: dispatch, stage: dev, service: intake }
  subject: { team: alpha, product: shop, stage: dev, service: orders }
  capability: { network: { ports: [8080], protocol: TCP } }
EOF
run bravo/good.yaml && ok "valid grant (correct directory) passes" || bad "valid grant should pass"

# 2. an AccessGrant (pre-existing kind) in the same directory tree → untouched, no-op pass
mk bravo/legacy-access.yaml <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: AccessGrant
metadata: { name: legacy }
spec:
  target: { team: bravo, product: dispatch }
  subject: group:team-alpha
  posture: view
EOF
run bravo/legacy-access.yaml && ok "AccessGrant is left alone (no-op)" || bad "AccessGrant should not be touched by this gate"

# 3. wrong directory (grant lives under alpha/ but target.team is bravo) → fail
mk alpha/wrong-dir.yaml <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: ServiceGrant
metadata: { name: wrong-dir }
spec:
  target: { team: bravo, product: dispatch, stage: dev, service: intake }
  subject: { team: alpha, product: shop, stage: dev, service: orders }
  capability: { network: { ports: [8080], protocol: TCP } }
EOF
run alpha/wrong-dir.yaml && bad "wrong directory team should fail" || ok "wrong directory team rejected (dir must equal target.team)"

# 4. missing required fields (no ports, no subject.service) → fail
mk bravo/missing-fields.yaml <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: ServiceGrant
metadata: { name: missing-fields }
spec:
  target: { team: bravo, product: dispatch, stage: dev, service: intake }
  subject: { team: alpha, product: shop, stage: dev }
  capability: { network: { protocol: TCP } }
EOF
run bravo/missing-fields.yaml && bad "missing required fields should fail" || ok "missing required fields rejected"

# 5. nonexistent owning Product on the subject side → fail
mk bravo/ghost-product.yaml <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: ServiceGrant
metadata: { name: ghost-product }
spec:
  target: { team: bravo, product: dispatch, stage: dev, service: intake }
  subject: { team: alpha, product: nonexistent, stage: dev, service: orders }
  capability: { network: { ports: [8080], protocol: TCP } }
EOF
run bravo/ghost-product.yaml && bad "nonexistent owning Product should fail" || ok "nonexistent owning Product rejected"

# 6. target Environment is hipaa/pci tier → fail
mk bravo/regulated.yaml <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: ServiceGrant
metadata: { name: regulated }
spec:
  target: { team: bravo, product: dispatch, stage: prod, service: intake }
  subject: { team: alpha, product: shop, stage: dev, service: orders }
  capability: { network: { ports: [8080], protocol: TCP } }
EOF
run bravo/regulated.yaml && bad "hipaa/pci target tier should fail" || ok "hipaa/pci target tier rejected"

[ "$fail" -eq 0 ] && echo "validate-service-grants tests passed." || { echo "validate-service-grants tests FAILED."; exit 1; }
