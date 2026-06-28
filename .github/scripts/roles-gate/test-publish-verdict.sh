#!/usr/bin/env bash
# Unit test for roles-gate/publish-verdict.sh — the meta-governance approval. Uses the test seams (no network).
# Run locally: bash .github/scripts/roles-gate/test-publish-verdict.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/publish-verdict.sh"

pass=0; fail=0
run() { # <expect> <label>  (env: ROLE_FILES ROLE_DELETED_FILES AUTHOR APPROVERS PERMS SOLO)
  local expect="$1" label="$2"
  REPO="o/r" HEAD_SHA="deadbeefcafe" STATUS_CONTEXT="Roles Approval" \
    AUTHOR="${AUTHOR:-author}" ROLE_FILES="${ROLE_FILES:-}" ROLE_DELETED_FILES="${ROLE_DELETED_FILES:-}" \
    SOLO_MAINTAINER="${SOLO:-false}" \
    VERDICT_TEST_APPROVERS="${APPROVERS:-}" VERDICT_TEST_PERMS="${PERMS:-}" VERDICT_DRY_RUN=1 \
    bash "$script" >/tmp/rverdict 2>&1
  local rc=$?
  if { [ "$expect" = ok ] && [ "$rc" -eq 0 ]; } || { [ "$expect" = deny ] && [ "$rc" -ne 0 ]; }; then
    pass=$((pass + 1)); echo "ok   - ${label}"
  else
    fail=$((fail + 1)); echo "FAIL - ${label} (expect ${expect}, rc ${rc}): $(cat /tmp/rverdict)"
  fi
}
reset_env() { unset ROLE_FILES ROLE_DELETED_FILES AUTHOR APPROVERS PERMS SOLO; }

reset_env; run ok "no role change → no approval needed"
reset_env; ROLE_FILES="gitops/roles/developer.yaml" \
  run deny "catalog change with no approval"
reset_env; ROLE_FILES="gitops/roles/developer.yaml" APPROVERS="rando" PERMS="rando=write" \
  run deny "catalog change approved by a non-admin"
reset_env; ROLE_FILES="gitops/roles/developer.yaml" APPROVERS="adm" PERMS="adm=admin" \
  run ok "catalog change approved by a repo admin"
reset_env; ROLE_DELETED_FILES="gitops/roles/old.yaml" APPROVERS="m" PERMS="m=maintain" \
  run ok "role deletion approved by a maintainer"
reset_env; ROLE_FILES="gitops/roles/developer.yaml" AUTHOR="adm" APPROVERS="adm" PERMS="adm=admin" \
  run deny "self-approval by the author is excluded"
reset_env; ROLE_FILES="gitops/roles/developer.yaml" AUTHOR="owner" SOLO=true PERMS="owner=admin" \
  run ok "solo-maintainer admin author self-attests"

echo "----"
echo "passed=${pass} failed=${fail}"
[ "$fail" -eq 0 ]
