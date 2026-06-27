#!/usr/bin/env bash
# People Gate — approval-routing-by-content. Publishes the `$STATUS_CONTEXT` (= "People Approval") commit status:
# success unless an access change on the CURRENT commit lacks its required APPROVED review (always ≠ author).
# Routes by WHAT changed (the base↔head grant diff per Person file), reading the team approver sets ONLY from
# `$BASE_DIR` (trusted) — never head — so a PR can't edit its own approver authority to self-approve:
#
#   a TEAM grant changes (add/remove `team: X`)  → an approval (≠ author) from team X's approver set
#                                                  (Team.spec.roles.releaseApprover) OR a repo admin/maintainer
#                                                  (the "team-lead" authority). Empty set ⇒ admin/maintainer only.
#   a PLATFORM grant changes (`scope: platform`) → an admin/maintainer approval (≠ author) — the "access-admin".
#   a Person is DELETED (offboarding)            → an admin/maintainer approval (≠ author) — the "access-admin".
#
# A pure no-op (e.g. a comment/handle edit with no grant change and no deletion) needs no approval.
#
# Env in: GH_TOKEN REPO PR_NUMBER HEAD_SHA AUTHOR BASE_DIR HEAD_DIR STATUS_CONTEXT RUN_URL
#         PEOPLE_FILES PEOPLE_DELETED_FILES
#   SOLO_MAINTAINER=true   single-admin project — an admin/maintainer author self-attests (separation-of-duties
#                          waived; flip off when a 2nd maintainer joins).
# Test seam (bypasses the gh calls + the status POST):
#   VERDICT_TEST_APPROVERS="login ..."   logins that APPROVED the current HEAD (author-exclusion applied here)
#   VERDICT_TEST_PERMS="login=admin ..." collaborator permission per login (admin|maintain|write|read|none)
#   VERDICT_DRY_RUN=1                     print the verdict + exit 0 (success) / 1 (failure); post no status
set -uo pipefail

REPO="${REPO:?}"; HEAD_SHA="${HEAD_SHA:?}"; STATUS_CONTEXT="${STATUS_CONTEXT:?}"
AUTHOR="$(printf '%s' "${AUTHOR:-}" | tr '[:upper:]' '[:lower:]')"
BASE="${BASE_DIR:-base}"
HEAD="${HEAD_DIR:-head}"
PEOPLE_FILES="${PEOPLE_FILES:-}"
PEOPLE_DELETED_FILES="${PEOPLE_DELETED_FILES:-}"

# Lowercased, deduped logins that APPROVED the current HEAD, author excluded. (Mirrors gitops publish-verdict.)
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

# Normalized (sorted-key, compact) grant set for a Person file → stdout, one JSON grant per line.
grants_of() { # <file>
  [ -f "$1" ] || return 0
  yq -o=json -I=0 '.spec.grants // [] | .[]' "$1" 2>/dev/null | jq -S -c '.' 2>/dev/null
}

APPROVERS=()
while IFS= read -r _a; do [ -n "$_a" ] && APPROVERS+=("$_a"); done < <(head_approvers)

# Is any approver (≠ author) a repo admin/maintainer? (the access-admin / fallback team-lead authority)
admin_approver=""
for a in "${APPROVERS[@]:-}"; do
  [ -z "$a" ] && continue
  perm="$(collab_perm "$a")"
  { [ "$perm" = "admin" ] || [ "$perm" = "maintain" ]; } && { admin_approver="$a"; break; }
done

# --- classify the change: which teams' grants moved, and is platform/deletion involved? --------------
teams_changed=" "          # space-delimited set of team names with an added/removed team grant
platform_changed=false
deletions=false
[ -n "${PEOPLE_DELETED_FILES// /}" ] && deletions=true

for pf in $PEOPLE_FILES; do
  bset="$(grants_of "${BASE}/${pf}")"
  hset="$(grants_of "${HEAD}/${pf}")"
  # symmetric difference (grants added or removed)
  diff_lines="$(comm -3 <(printf '%s\n' "$bset" | sort -u) <(printf '%s\n' "$hset" | sort -u) | sed 's/^\t//')"
  [ -z "${diff_lines//[$' \t\n']/}" ] && continue
  while IFS= read -r gj; do
    [ -z "$gj" ] && continue
    t="$(printf '%s' "$gj" | jq -r '.team // empty' 2>/dev/null)"
    s="$(printf '%s' "$gj" | jq -r '.scope // empty' 2>/dev/null)"
    if [ -n "$t" ]; then
      case "$teams_changed" in *" $t "*) ;; *) teams_changed="${teams_changed}${t} " ;; esac
    elif [ -n "$s" ]; then
      platform_changed=true
    fi
  done <<<"$diff_lines"
done

state=success
desc="no approval requirement for this PR"
ok=true

# Solo-maintainer escape (single-admin project) — admin/maintainer author self-attests. Mirrors gitops-gate.
if [ "${SOLO_MAINTAINER:-false}" = "true" ] && [ -n "$AUTHOR" ]; then
  author_perm="$(collab_perm "$AUTHOR")"
  if [ "$author_perm" = "admin" ] || [ "$author_perm" = "maintain" ]; then
    teams_changed=" "; platform_changed=false; deletions=false
    desc="solo-maintainer self-attest: admin author ${AUTHOR} at ${HEAD_SHA:0:7} (SOLO_MAINTAINER set — separation-of-duties waived)"
  fi
fi

# access-admin surfaces: a platform-role grant change, or a Person deletion (offboarding).
if [ "$ok" = true ] && { [ "$platform_changed" = true ] || [ "$deletions" = true ]; }; then
  what="platform-role grant"; [ "$deletions" = true ] && what="person offboarding"
  if [ -n "$admin_approver" ]; then
    desc="approved by ${admin_approver} at ${HEAD_SHA:0:7} — ${what} (access-admin)"
  else
    ok=false; state=failure
    desc="awaiting an admin/maintainer approval (≠ author) of ${HEAD_SHA:0:7} — ${what} (access-admin)"
  fi
fi

# team grants: each changed team needs its approver set (≠ author) OR an admin/maintainer (team-lead authority).
if [ "$ok" = true ] && [ -n "${teams_changed// /}" ]; then
  for team in $teams_changed; do
    tfile="${BASE}/gitops/teams/${team}.yaml"; [ -f "$tfile" ] || tfile="${BASE}/gitops/teams/${team}.yml"
    set_logins=""
    [ -f "$tfile" ] && set_logins="$(yq -r '(.spec.roles.releaseApprover // [])[]' "$tfile" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed '/^$/d' | sort -u)"
    matched=""
    for a in "${APPROVERS[@]:-}"; do
      [ -z "$a" ] && continue
      if printf '%s\n' "$set_logins" | grep -qx "$a"; then matched="$a"; break; fi
    done
    [ -z "$matched" ] && [ -n "$admin_approver" ] && matched="$admin_approver"   # admin/maintainer = team-lead fallback
    if [ -n "$matched" ]; then
      desc="approved by ${matched} at ${HEAD_SHA:0:7} — team '${team}' grant (team-lead)"
    else
      ok=false; state=failure
      desc="awaiting a team-lead approval (≠ author) of ${HEAD_SHA:0:7} for team '${team}' grant — an approver in ${team}'s set or a repo admin/maintainer"
      break
    fi
  done
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
