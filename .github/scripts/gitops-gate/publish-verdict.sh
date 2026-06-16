#!/usr/bin/env bash
# Shared approval verdict for the gitops + teams gates. Publishes the `$STATUS_CONTEXT` commit status: success
# unless a PRIVILEGED change on the CURRENT commit lacks its required APPROVED review (always ≠ author). Reads the
# approver sets + tiers ONLY from `$BASE_DIR` (the trusted base checkout) — never head/PR input — so a PR can't
# edit its own approver list to self-approve. Used by:
#   - gitops-gate  → STATUS_CONTEXT="gitops Approval"  (deletions #283, prod promotion #377, Product roles edit #501)
#   - teams-gate   → STATUS_CONTEXT="Teams Approval"   (Team roles edit #501)
#
# Reasons (any set → an approval is required; otherwise success):
#   DELETIONS=true              registry deletion          → an admin/maintainer approval (ADR-062 #283)
#   PRODUCT_ROLES_CHANGES=true  a Product spec.roles edit  → an admin/maintainer approval (#501 two-step guard)
#   TEAM_ROLES_CHANGES=true     a Team spec.roles edit     → an admin/maintainer approval (#501 two-step guard)
#   PROD_RELEASES="<files...>"  prod promotion             → an approval from the (team,product) RELEASE-APPROVER
#                               set: Product.spec.roles.releaseApprover else Team.spec.roles.releaseApprover, ≠
#                               author. pci/hipaa env tier → ≥2 DISTINCT approvers. Empty set → FAIL CLOSED.
#
# Env: GH_TOKEN REPO PR_NUMBER HEAD_SHA AUTHOR BASE_DIR STATUS_CONTEXT RUN_URL + the reason flags above.
# Test seam (bypasses the two gh api calls + the status POST):
#   VERDICT_TEST_APPROVERS="login ..."   logins that APPROVED the current HEAD (author-exclusion is applied here)
#   VERDICT_TEST_PERMS="login=admin ..." collaborator permission per login (admin|maintain|write|read|none)
#   VERDICT_DRY_RUN=1                     print the verdict + exit 0 (success) / 1 (failure); post no status
set -uo pipefail

REPO="${REPO:?}"; HEAD_SHA="${HEAD_SHA:?}"; STATUS_CONTEXT="${STATUS_CONTEXT:?}"
AUTHOR="$(printf '%s' "${AUTHOR:-}" | tr '[:upper:]' '[:lower:]')"
BASE="${BASE_DIR:-base}"
DELETIONS="${DELETIONS:-false}"
PROD_RELEASES="${PROD_RELEASES:-}"
PRODUCT_ROLES_CHANGES="${PRODUCT_ROLES_CHANGES:-false}"
TEAM_ROLES_CHANGES="${TEAM_ROLES_CHANGES:-false}"

# Lowercased, deduped logins that APPROVED the current HEAD, with the PR author excluded.
head_approvers() {
  local raw
  if [ -n "${VERDICT_TEST_APPROVERS+x}" ]; then
    # shellcheck disable=SC2086  # intentional word-split of the space-separated test seam
    raw="$(printf '%s\n' $VERDICT_TEST_APPROVERS)"
  else
    raw="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
      --jq 'group_by(.user.login) | map(max_by(.submitted_at))
            | .[] | select(.state=="APPROVED" and .commit_id==env.HEAD_SHA) | .user.login')"
  fi
  printf '%s\n' "$raw" | tr '[:upper:]' '[:lower:]' | sed '/^$/d' | sort -u \
    | { if [ -n "$AUTHOR" ]; then grep -vx -- "$AUTHOR" || true; else cat; fi; }
}

# Collaborator permission for a login: admin|maintain|write|read|none.
collab_perm() {
  if [ -n "${VERDICT_TEST_PERMS+x}" ]; then
    # shellcheck disable=SC2086  # intentional word-split of the space-separated test seam
    printf '%s\n' $VERDICT_TEST_PERMS | tr ' ' '\n' | sed -n "s/^${1}=//p" | head -1
  else
    gh api "repos/${REPO}/collaborators/${1}/permission" --jq .permission 2>/dev/null || echo none
  fi
}

# Portable (bash 3.2+) — no mapfile.
APPROVERS=()
while IFS= read -r _a; do [ -n "$_a" ] && APPROVERS+=("$_a"); done < <(head_approvers)

state=success
desc="no approval requirement for this PR"
ok=true

# Privileged surfaces (registry deletion / approver-list edit): an admin OR maintainer approval, ≠ author.
priv=""
[ "$DELETIONS" = "true" ] && priv="registry deletion (ADR-062 #283)"
{ [ "$PRODUCT_ROLES_CHANGES" = "true" ] || [ "$TEAM_ROLES_CHANGES" = "true" ]; } && priv="approver-list change (#501)"
if [ -n "$priv" ]; then
  found=""
  for a in "${APPROVERS[@]:-}"; do
    [ -z "$a" ] && continue
    perm="$(collab_perm "$a")"
    { [ "$perm" = "admin" ] || [ "$perm" = "maintain" ]; } && { found="$a"; break; }
  done
  if [ -n "$found" ]; then
    desc="approved by ${found} at ${HEAD_SHA:0:7} — ${priv}"
  else
    ok=false; state=failure
    desc="awaiting an admin/maintainer approval (≠ author) of ${HEAD_SHA:0:7} — ${priv}"
  fi
fi

# Prod promotion: an approval from the per-(team,product) release-approver set (Product override else Team).
if [ "$ok" = true ] && [ -n "$PROD_RELEASES" ]; then
  for rel in $PROD_RELEASES; do
    team="$(basename "$(dirname "$(dirname "$rel")")")"
    product="$(basename "$(dirname "$rel")")"
    fname="$(basename "$rel")"
    pfile="${BASE}/gitops/products/${team}/${product}.yaml"
    tfile="${BASE}/gitops/teams/${team}.yaml"
    set_logins=""
    [ -f "$pfile" ] && set_logins="$(yq -r '(.spec.roles.releaseApprover // [])[]' "$pfile" 2>/dev/null)"
    if [ -z "$set_logins" ] && [ -f "$tfile" ]; then
      set_logins="$(yq -r '(.spec.roles.releaseApprover // [])[]' "$tfile" 2>/dev/null)"
    fi
    set_logins="$(printf '%s\n' "$set_logins" | tr '[:upper:]' '[:lower:]' | sed '/^$/d' | sort -u)"
    if [ -z "$set_logins" ]; then
      ok=false; state=failure
      desc="no release-approver configured for ${team}/${product} — prod blocked (fail-closed, #501)"; break
    fi
    need=1
    efile="${BASE}/gitops/environments/${team}/${product}/${fname}"
    [ -f "$efile" ] && case "$(yq -r '.spec.tier // "standard"' "$efile" 2>/dev/null)" in pci | hipaa) need=2 ;; esac
    matched=0
    for a in "${APPROVERS[@]:-}"; do
      [ -z "$a" ] && continue
      printf '%s\n' "$set_logins" | grep -qx "$a" && matched=$((matched + 1))
    done
    if [ "$matched" -lt "$need" ]; then
      ok=false; state=failure
      desc="prod ${team}/${product} needs ${need} release-approver approval(s) ≠ author of ${HEAD_SHA:0:7}; have ${matched}"; break
    fi
    desc="prod ${team}/${product} approved (${matched}/${need}) at ${HEAD_SHA:0:7}"
  done
fi

desc="${desc:0:140}" # GitHub commit-status description limit

if [ -n "${VERDICT_DRY_RUN:-}" ]; then
  echo "${STATUS_CONTEXT} = ${state} — ${desc}"
  [ "$state" = success ]
  exit $?
fi
gh api --method POST "repos/${REPO}/statuses/${HEAD_SHA}" \
  -f state="$state" -f context="$STATUS_CONTEXT" \
  -f description="$desc" -f target_url="${RUN_URL:-}" >/dev/null
echo "${STATUS_CONTEXT} = ${state} — ${desc}"
