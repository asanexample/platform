#!/usr/bin/env bash
# Unit test for detect-lifecycle-decommission.sh — asserts a PR transitioning an Environment into a suspend
# state (spec.lifecycle.phase ∈ decommissioning|suspended) emits decommission=true (→ excluded from
# auto-merge), while active / reactivate / non-lifecycle edits emit false. Run:
#   bash .github/scripts/gitops-gate/test-detect-lifecycle-decommission.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/detect-lifecycle-decommission.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::yq required"; exit 1; }

head="$(mktemp -d)"
trap 'rm -rf "$head"' EXIT
mkdir -p "$head/gitops/environments/alpha/shop"
cat >"$head/gitops/environments/alpha/shop/dev.yaml" <<'Y'
kind: XEnvironment
spec: { team: alpha, product: shop, stage: dev, lifecycle: { phase: active } }
Y
cat >"$head/gitops/environments/alpha/shop/prod.yaml" <<'Y'
kind: XEnvironment
spec: { team: alpha, product: shop, stage: prod, lifecycle: { phase: decommissioning } }
Y
cat >"$head/gitops/environments/alpha/shop/test.yaml" <<'Y'
kind: XEnvironment
spec: { team: alpha, product: shop, stage: test }
Y

pass=0; failc=0
# run <expect true|false> <name> <ENVIRONMENT_FILES...>
run() {
  local expect="$1" name="$2"; shift 2
  local got
  got="$(ENVIRONMENT_FILES="$*" HEAD_DIR="$head" GITHUB_OUTPUT=/dev/stdout bash "$script" | sed -n 's/^decommission=//p')"
  if [ "$got" = "$expect" ]; then echo "  ✓ ${name} (${got})"; pass=$((pass+1))
  else echo "  ✗ ${name}: expected ${expect}, got ${got}"; failc=$((failc+1)); fi
}

echo "== detect-lifecycle-decommission.sh unit tests =="
run true  "decommissioning env in the PR"        "gitops/environments/alpha/shop/prod.yaml"
run false "active env (reactivate / steady)"     "gitops/environments/alpha/shop/dev.yaml"
run false "no lifecycle block (defaults active)" "gitops/environments/alpha/shop/test.yaml"
run true  "mixed: one decommissioning suffices"  "gitops/environments/alpha/shop/dev.yaml gitops/environments/alpha/shop/prod.yaml"
run false "no env files"                          ""

echo "── ${pass} passed, ${failc} failed ──"
[ "$failc" -eq 0 ] || exit 1
