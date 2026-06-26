#!/usr/bin/env bash
# Unit test for render-environments.sh — the Environment composition-render gate. The real render needs crank
# + docker + function images, so we stub `crossplane` and `docker` as functions and exercise the script's
# CONTROL LOGIC instead: the trusted-input guard, the per-claim render-success/failure/empty-output handling,
# and the accumulate-then-exit-rc behaviour. Run locally: bash .github/scripts/gitops-gate/test-render-environments.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/render-environments.sh"

# Stub docker (the `docker info` reachability probe) and crossplane (the render). $MOCK_RENDER selects the
# render outcome: ok → emits a manifest with `kind:`; nokind → emits output without `kind:`; fail → exit 1.
docker() { return 0; }
crossplane() {
  case "${1:-}" in
    render)
      case "${MOCK_RENDER:-ok}" in
        fail) echo "render error: bad service config"; return 1 ;;
        nokind) echo "status: rendered-but-empty" ;;
        *) printf 'apiVersion: example.org/v1\nkind: Composite\n' ;;
      esac ;;
  esac
}
export -f docker crossplane

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
head="${work}/head"

# A base with the trusted render inputs present (paths the script expects), and one without the Composition.
mk_base() { # <dir> <with-composition: yes|no>
  local b="$1" comp="$2"
  mkdir -p "${b}/infra/modules/crossplane/.environment-api-tests/render" \
           "${b}/infra/modules/crossplane/charts/environment-api/files"
  : >"${b}/infra/modules/crossplane/.environment-api-tests/render/functions.yaml"
  : >"${b}/infra/modules/crossplane/.environment-api-tests/render/environmentconfig.yaml"
  [ "$comp" = yes ] && : >"${b}/infra/modules/crossplane/charts/environment-api/files/composition.yaml"
}
base="${work}/base";        mk_base "$base" yes
base_noc="${work}/base_noc"; mk_base "$base_noc" no

# A head claim file that exists (content is irrelevant — the render is stubbed).
mkdir -p "${head}/gitops/environments/alpha/shop"
: >"${head}/gitops/environments/alpha/shop/dev.yaml"

pass=0; failc=0
# run <expect: ok|deny> <name> <MOCK_RENDER> <BASE_DIR> <ENVIRONMENT_FILES...>
run() {
  local expect="$1" name="$2" mock="$3" b="$4"; shift 4
  MOCK_RENDER="$mock" BASE_DIR="$b" HEAD_DIR="$head" ENVIRONMENT_FILES="$*" bash "$script" >/dev/null 2>&1
  local rc=$?
  local got=ok; [ $rc -ne 0 ] && got=deny
  if [ "$got" = "$expect" ]; then echo "  ✓ ${name} (${got})"; pass=$((pass+1))
  else echo "  ✗ ${name}: expected ${expect}, got ${got} (rc=${rc})"; failc=$((failc+1)); fi
}

echo "== render-environments.sh unit tests =="
run ok   "render succeeds (emits kind:)"   ok     "$base"     "gitops/environments/alpha/shop/dev.yaml"
run ok   "no environment files (empty)"    ok     "$base"     ""
run deny "render fails"                     fail   "$base"     "gitops/environments/alpha/shop/dev.yaml"
run deny "render output has no kind:"       nokind "$base"     "gitops/environments/alpha/shop/dev.yaml"
run deny "claim missing from head checkout" ok     "$base"     "gitops/environments/alpha/shop/ghost.yaml"
run deny "missing trusted Composition"      ok     "$base_noc" "gitops/environments/alpha/shop/dev.yaml"

echo "── ${pass} passed, ${failc} failed ──"
[ "$failc" -eq 0 ] || exit 1
