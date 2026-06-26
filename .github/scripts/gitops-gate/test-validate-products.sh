#!/usr/bin/env bash
# Unit test for validate-products.sh — the Product-registry gate (schema shape + enums + ownership).
# Self-contained: builds throwaway BASE_DIR (Team list) + HEAD_DIR (Product files) fixtures, runs the
# script with various PRODUCT_FILES, and asserts the exit code (ok = rc 0, deny = rc != 0).
# Run locally: bash .github/scripts/gitops-gate/test-validate-products.sh   (needs mikefarah yq)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/validate-products.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::yq required"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
base="${work}/base"
head="${work}/head"

# Trusted base: the owning Team must exist (ownership check). Team alpha exists; beta does NOT.
mkdir -p "${base}/gitops/teams"
cat >"${base}/gitops/teams/alpha.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Team
metadata: { name: alpha }
spec: { ssoGroup: alpha-team }
Y

# Helper to write a head Product file at gitops/products/<dir>/<name>.yaml
prod() { # <relpath-under-gitops/products> <yaml-body>
  local rel="gitops/products/$1"; mkdir -p "${head}/$(dirname "$rel")"; cat >"${head}/${rel}"
}

# A valid product (alpha/shop): team alpha, metadata.name alpha-shop, repo owner/repo, tenancy pooled.
prod "alpha/shop.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-shop }
spec: { team: alpha, repo: asanexample/alpha-shop, tenancy: pooled }
Y
prod "alpha/approver.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-approver }
spec:
  team: alpha
  repo: asanexample/alpha-approver
  roles: { releaseApprover: [octocat, hubot] }
Y
prod "alpha/badkind.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Widget
metadata: { name: alpha-badkind }
spec: { team: alpha, repo: asanexample/x }
Y
prod "alpha/noteam.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-noteam }
spec: { repo: asanexample/x }
Y
prod "alpha/namemismatch.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: wrong-name }
spec: { team: alpha, repo: asanexample/x }
Y
prod "alpha/badtenancy.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-badtenancy }
spec: { team: alpha, repo: asanexample/x, tenancy: solo }
Y
prod "alpha/unknownkey.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-unknownkey }
spec: { team: alpha, repo: asanexample/x, tennancy: pooled }
Y
prod "alpha/badrepo.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-badrepo }
spec: { team: alpha, repo: justrepo }
Y
prod "alpha/emptyapprover.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-emptyapprover }
spec: { team: alpha, repo: asanexample/x, roles: { releaseApprover: [] } }
Y
# Owning team 'beta' has no gitops/teams/beta.yaml in base → ownership failure.
prod "beta/orphan.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: beta-orphan }
spec: { team: beta, repo: asanexample/x }
Y
# Directory 'beta' disagrees with spec.team 'alpha' → path/team mismatch.
prod "beta/wrongdir.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: alpha-wrongdir }
spec: { team: alpha, repo: asanexample/x }
Y

pass=0; failc=0
# run <expect: ok|deny> <name> <PRODUCT_FILES...>
run() {
  local expect="$1" name="$2"; shift 2
  BASE_DIR="$base" HEAD_DIR="$head" PRODUCT_FILES="$*" bash "$script" >/dev/null 2>&1
  local rc=$?
  local got=ok; [ $rc -ne 0 ] && got=deny
  if [ "$got" = "$expect" ]; then echo "  ✓ ${name} (${got})"; pass=$((pass+1))
  else echo "  ✗ ${name}: expected ${expect}, got ${got} (rc=${rc})"; failc=$((failc+1)); fi
}

echo "== validate-products.sh unit tests =="
run ok   "valid product"                       "gitops/products/alpha/shop.yaml"
run ok   "valid releaseApprover list"          "gitops/products/alpha/approver.yaml"
run ok   "no product files (empty)"            ""
run deny "wrong kind"                          "gitops/products/alpha/badkind.yaml"
run deny "missing spec.team"                   "gitops/products/alpha/noteam.yaml"
run deny "metadata.name mismatch"              "gitops/products/alpha/namemismatch.yaml"
run deny "invalid tenancy enum"                "gitops/products/alpha/badtenancy.yaml"
run deny "unknown spec key (typo)"             "gitops/products/alpha/unknownkey.yaml"
run deny "repo not owner/repo"                 "gitops/products/alpha/badrepo.yaml"
run deny "empty releaseApprover override"      "gitops/products/alpha/emptyapprover.yaml"
run deny "owning Team does not exist"          "gitops/products/beta/orphan.yaml"
run deny "directory != spec.team"              "gitops/products/beta/wrongdir.yaml"
run deny "file missing from head checkout"     "gitops/products/alpha/ghost.yaml"
# A clean file alongside a bad one still denies (accumulate-then-fail-closed).
run deny "valid + invalid together"            "gitops/products/alpha/shop.yaml gitops/products/alpha/badkind.yaml"

echo "── ${pass} passed, ${failc} failed ──"
[ "$failc" -eq 0 ] || exit 1
