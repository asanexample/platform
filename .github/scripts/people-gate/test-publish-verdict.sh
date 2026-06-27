#!/usr/bin/env bash
# Unit test for people-gate/publish-verdict.sh — the approval-routing-by-content. Uses the script's test seams
# (VERDICT_TEST_APPROVERS / VERDICT_TEST_PERMS / VERDICT_DRY_RUN) so it makes no network calls. Builds base/head
# Person fixtures, then asserts the verdict (rc 0 = success / rc 1 = failure) for each routing case.
# Run locally: bash .github/scripts/people-gate/test-publish-verdict.sh   (needs mikefarah yq + jq)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/publish-verdict.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::yq required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error::jq required"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
base="${work}/base"; head="${work}/head"
mkdir -p "${base}/gitops/teams" "${base}/gitops/people" "${head}/gitops/people"

# team alpha's approver set = lead-alpha (the team-lead authority).
cat >"${base}/gitops/teams/alpha.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: Team
metadata: { name: alpha }
spec: { ssoGroup: Dev-alpha, roles: { releaseApprover: [lead-alpha] } }
Y

mkperson() { # <base|head> <name> <grants-inline>
  local root="$base"; [ "$1" = head ] && root="$head"
  cat >"${root}/gitops/people/$2.yaml" <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: $2 }
spec: { person: anchor-$2, grants: $3 }
Y
}

pass=0; fail=0
run() { # <expect ok|deny> <label> ; env vars set by caller: PEOPLE_FILES PEOPLE_DELETED_FILES AUTHOR APPROVERS PERMS SOLO
  local expect="$1" label="$2"
  REPO="o/r" HEAD_SHA="deadbeefcafe" STATUS_CONTEXT="People Approval" \
    AUTHOR="${AUTHOR:-author}" BASE_DIR="$base" HEAD_DIR="$head" \
    PEOPLE_FILES="${PEOPLE_FILES:-}" PEOPLE_DELETED_FILES="${PEOPLE_DELETED_FILES:-}" \
    SOLO_MAINTAINER="${SOLO:-false}" \
    VERDICT_TEST_APPROVERS="${APPROVERS:-}" VERDICT_TEST_PERMS="${PERMS:-}" VERDICT_DRY_RUN=1 \
    bash "$script" >/tmp/verdict_out 2>&1
  local rc=$?
  if { [ "$expect" = ok ] && [ "$rc" -eq 0 ]; } || { [ "$expect" = deny ] && [ "$rc" -ne 0 ]; }; then
    pass=$((pass + 1)); echo "ok   - ${label}"
  else
    fail=$((fail + 1)); echo "FAIL - ${label} (expect ${expect}, rc ${rc}): $(cat /tmp/verdict_out)"
  fi
}
reset_env() { unset PEOPLE_FILES PEOPLE_DELETED_FILES AUTHOR APPROVERS PERMS SOLO; }

# --- new team grant → team-lead authority -----------------------------------------------------------
mkperson head t1 '[{ role: developer, team: alpha }]'
reset_env; PEOPLE_FILES=gitops/people/t1.yaml APPROVERS="lead-alpha" PERMS="lead-alpha=write" \
  run ok "team grant approved by the team's approver"
reset_env; PEOPLE_FILES=gitops/people/t1.yaml APPROVERS="rando" PERMS="rando=write" \
  run deny "team grant approved by a non-approver, non-admin"
reset_env; PEOPLE_FILES=gitops/people/t1.yaml APPROVERS="adm" PERMS="adm=admin" \
  run ok "team grant approved by a repo admin (team-lead fallback)"
reset_env; PEOPLE_FILES=gitops/people/t1.yaml \
  run deny "team grant with no approval"

# --- new platform grant → access-admin --------------------------------------------------------------
mkperson head p1 '[{ role: platform-admin, scope: platform }]'
reset_env; PEOPLE_FILES=gitops/people/p1.yaml APPROVERS="lead-alpha" PERMS="lead-alpha=write" \
  run deny "platform grant approved by a non-admin"
reset_env; PEOPLE_FILES=gitops/people/p1.yaml APPROVERS="adm" PERMS="adm=admin" \
  run ok "platform grant approved by a repo admin (access-admin)"
reset_env; PEOPLE_FILES=gitops/people/p1.yaml APPROVERS="m" PERMS="m=maintain" \
  run ok "platform grant approved by a maintainer (access-admin)"

# --- person deletion (offboarding) → access-admin ---------------------------------------------------
mkperson base gone '[{ role: developer, team: alpha }]'
reset_env; PEOPLE_DELETED_FILES=gitops/people/gone.yaml APPROVERS="adm" PERMS="adm=admin" \
  run ok "offboarding approved by a repo admin"
reset_env; PEOPLE_DELETED_FILES=gitops/people/gone.yaml APPROVERS="rando" PERMS="rando=write" \
  run deny "offboarding approved by a non-admin"

# --- no-op (no grant change, no deletion) → no approval needed ---------------------------------------
mkperson base noop '[{ role: developer, team: alpha }]'
mkperson head noop '[{ role: developer, team: alpha }]'
reset_env; PEOPLE_FILES=gitops/people/noop.yaml \
  run ok "no grant change needs no approval"

# --- author exclusion: the only approver is the author → not counted --------------------------------
reset_env; PEOPLE_FILES=gitops/people/t1.yaml AUTHOR="lead-alpha" APPROVERS="lead-alpha" PERMS="lead-alpha=write" \
  run deny "self-approval by the author is excluded"

# --- solo-maintainer: admin author self-attests -----------------------------------------------------
reset_env; PEOPLE_FILES=gitops/people/p1.yaml AUTHOR="owner" SOLO=true PERMS="owner=admin" \
  run ok "solo-maintainer admin author self-attests a platform grant"

echo "----"
echo "passed=${pass} failed=${fail}"
[ "$fail" -eq 0 ]
