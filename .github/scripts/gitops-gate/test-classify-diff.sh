#!/usr/bin/env bash
# Unit test for classify-diff.sh — the diff classifier that splits a PR's changed files into the registry
# surfaces (product/environment/release/agent), flags prod-stage releases, deletions, and non-registry
# changes. Stubs `gh` with a function that returns a fixed file list (the post-`--jq` array shape), runs the
# script with GITHUB_OUTPUT pointed at a temp file, and asserts the emitted key=value pairs.
# Run locally: bash .github/scripts/gitops-gate/test-classify-diff.sh   (needs jq)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/classify-diff.sh"
command -v jq >/dev/null 2>&1 || { echo "::error::jq required"; exit 1; }

# Stub the GitHub CLI: classify-diff calls `gh api ... --jq '[.[]|{filename,status,previous_filename}]'`,
# so emit that already-shaped array verbatim from $MOCK_FILES (args are ignored).
gh() { printf '%s' "${MOCK_FILES}"; }
export -f gh

pass=0; failc=0
# check <name> <mock-json-array> <key=expected>...
check() {
  local name="$1" mock="$2"; shift 2
  local out; out="$(mktemp)"
  MOCK_FILES="$mock" REPO="o/r" PR_NUMBER="1" GITHUB_OUTPUT="$out" bash "$script" >/dev/null 2>&1
  local ok=1 msg=""
  local kv k want got
  for kv in "$@"; do
    k="${kv%%=*}"; want="${kv#*=}"
    got="$(sed -n "s/^${k}=//p" "$out" | tail -1)"
    [ "$got" = "$want" ] || { ok=0; msg="${msg} [${k}: want '${want}' got '${got}']"; }
  done
  rm -f "$out"
  if [ "$ok" = 1 ]; then echo "  ✓ ${name}"; pass=$((pass+1))
  else echo "  ✗ ${name}:${msg}"; failc=$((failc+1)); fi
}

f() { # build a one-element file array: <filename> <status> [previous]
  jq -nc --arg f "$1" --arg s "$2" --arg p "${3:-}" '[{filename:$f,status:$s,previous_filename:$p}]'
}

echo "== classify-diff.sh unit tests =="

check "product added" "$(f gitops/products/alpha/shop.yaml added)" \
  product_files=gitops/products/alpha/shop.yaml any=true deletions=false non_registry_changes=false

check "environment modified" "$(f gitops/environments/alpha/shop/dev.yaml modified)" \
  environment_files=gitops/environments/alpha/shop/dev.yaml any=true

check "release (non-prod) → no prod_release" "$(f gitops/releases/alpha/shop/dev.yaml added)" \
  release_files=gitops/releases/alpha/shop/dev.yaml prod_release_files= any=true

check "prod release → prod_release set" "$(f gitops/releases/alpha/shop/prod.yaml added)" \
  release_files=gitops/releases/alpha/shop/prod.yaml prod_release_files=gitops/releases/alpha/shop/prod.yaml

check "customer-prod release → prod_release set" "$(f gitops/releases/alpha/shop/acme-prod.yaml added)" \
  prod_release_files=gitops/releases/alpha/shop/acme-prod.yaml

check "agent claim added" "$(f gitops/agents/triage-copilot.yaml added)" \
  agent_files=gitops/agents/triage-copilot.yaml any=true

check "grant added (per-team directory, ADR-101 ServiceGrant convention)" "$(f gitops/grants/bravo/allow-shop-to-intake.yaml added)" \
  grant_files=gitops/grants/bravo/allow-shop-to-intake.yaml any=true

check "grant added (flat, pre-existing ADR-068 AccessGrant convention)" "$(f gitops/grants/bravo-reads-alpha-shop.yaml added)" \
  grant_files=gitops/grants/bravo-reads-alpha-shop.yaml any=true

check "grant README untouched (excluded, .md not .ya?ml)" "$(f gitops/grants/README.md modified)" \
  grant_files= non_registry_changes=true any=false

check "non-registry file" "$(f README.md modified)" \
  non_registry_changes=true any=false deletions=false

check "registry file removed" "$(f gitops/products/alpha/shop.yaml removed)" \
  deletions=true deleted_files=gitops/products/alpha/shop.yaml any=false non_registry_changes=false

check "renamed registry → non-registry (drop)" "$(f docs/moved.md renamed gitops/products/alpha/shop.yaml)" \
  non_registry_changes=true deletions=true deleted_files=gitops/products/alpha/shop.yaml

check "empty changeset" '[]' \
  any=false deletions=false non_registry_changes=false

check "mixed product + non-registry" \
  "$(jq -nc '[{filename:"gitops/products/alpha/shop.yaml",status:"added",previous_filename:""},{filename:"README.md",status:"modified",previous_filename:""}]')" \
  product_files=gitops/products/alpha/shop.yaml non_registry_changes=true any=true

echo "── ${pass} passed, ${failc} failed ──"
[ "$failc" -eq 0 ] || exit 1
