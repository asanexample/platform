#!/usr/bin/env bash
# Roles Gate — meta-governance approval (§3.6). Publishes the `$STATUS_CONTEXT` (= "Roles Approval") commit
# status: ANY change to the role catalog (add / modify / delete a WorkforceRole) re-permissions everyone who
# holds that role, so it requires an admin/maintainer approval (≠ author) — two-person control, grantor ≠
# beneficiary. A PR that changes no role files needs no approval.
#
# Env in: GH_TOKEN REPO PR_NUMBER HEAD_SHA AUTHOR STATUS_CONTEXT RUN_URL ROLE_FILES ROLE_DELETED_FILES
#   SOLO_MAINTAINER=true   single-admin project — an admin/maintainer author self-attests.
# Test seam: VERDICT_TEST_APPROVERS / VERDICT_TEST_PERMS / VERDICT_DRY_RUN (as in the people/gitops verdicts).
set -uo pipefail

REPO="${REPO:?}"; HEAD_SHA="${HEAD_SHA:?}"; STATUS_CONTEXT="${STATUS_CONTEXT:?}"
AUTHOR="$(printf '%s' "${AUTHOR:-}" | tr '[:upper:]' '[:lower:]')"
ROLE_FILES="${ROLE_FILES:-}"
ROLE_DELETED_FILES="${ROLE_DELETED_FILES:-}"

head_approvers() {
  local raw
  if [ -n "${VERDICT_TEST_APPROVERS+x}" ]; then
    # shellcheck disable=SC2086
    raw="$(printf '%s\n' $VERDICT_TEST_APPROVERS)"
  else
    raw="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
      --jq 'group_by(.user.login) | map(max_by(.submitted_at))
            | .[] | select(.state=="APPROVED" and .commit_id==env.HEAD_SHA) | .user.login')"
  fi
  printf '%s\n' "$raw" | tr '[:upper:]' '[:lower:]' | sed '/^$/d' | sort -u \
    | { if [ -n "$AUTHOR" ]; then grep -vx -- "$AUTHOR" || true; else cat; fi; }
}

collab_perm() {
  if [ -n "${VERDICT_TEST_PERMS+x}" ]; then
    # shellcheck disable=SC2086
    printf '%s\n' $VERDICT_TEST_PERMS | tr ' ' '\n' | sed -n "s/^${1}=//p" | head -1
  else
    gh api "repos/${REPO}/collaborators/${1}/permission" --jq .permission 2>/dev/null || echo none
  fi
}

APPROVERS=()
while IFS= read -r _a; do [ -n "$_a" ] && APPROVERS+=("$_a"); done < <(head_approvers)

catalog_changed=false
{ [ -n "${ROLE_FILES// /}" ] || [ -n "${ROLE_DELETED_FILES// /}" ]; } && catalog_changed=true

state=success
desc="no role-catalog change in this PR"
ok=true

# Solo-maintainer escape — admin/maintainer author self-attests the catalog change.
if [ "$catalog_changed" = true ] && [ "${SOLO_MAINTAINER:-false}" = "true" ] && [ -n "$AUTHOR" ]; then
  author_perm="$(collab_perm "$AUTHOR")"
  if [ "$author_perm" = "admin" ] || [ "$author_perm" = "maintain" ]; then
    catalog_changed=false
    desc="solo-maintainer self-attest: admin author ${AUTHOR} at ${HEAD_SHA:0:7} (SOLO_MAINTAINER set — separation-of-duties waived)"
  fi
fi

if [ "$ok" = true ] && [ "$catalog_changed" = true ]; then
  found=""
  for a in "${APPROVERS[@]:-}"; do
    [ -z "$a" ] && continue
    perm="$(collab_perm "$a")"
    { [ "$perm" = "admin" ] || [ "$perm" = "maintain" ]; } && { found="$a"; break; }
  done
  if [ -n "$found" ]; then
    desc="approved by ${found} at ${HEAD_SHA:0:7} — role-catalog change (meta-governance, §3.6)"
  else
    ok=false; state=failure
    desc="awaiting an admin/maintainer approval (≠ author) of ${HEAD_SHA:0:7} — role-catalog change re-permissions every holder (§3.6)"
  fi
fi

desc="${desc:0:140}"

if [ -n "${VERDICT_DRY_RUN:-}" ]; then
  echo "${STATUS_CONTEXT} = ${state} — ${desc}"
  [ "$state" = success ]; exit $?
fi
gh api --method POST "repos/${REPO}/statuses/${HEAD_SHA}" \
  -f state="$state" -f context="$STATUS_CONTEXT" \
  -f description="$desc" -f target_url="${RUN_URL:-}" >/dev/null
echo "${STATUS_CONTEXT} = ${state} — ${desc}"
