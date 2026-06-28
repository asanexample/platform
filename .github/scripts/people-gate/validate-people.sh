#!/usr/bin/env bash
# People Gate — validate Person-registry PRs (gitops/people/**) before merge (sibling of the Teams Gate).
#
# SECURITY MODEL (mirrors teams-gate): this script + everything authoritative (the Team list that grants are
# checked against) is read from the TRUSTED BASE checkout. The PR's Person CRs are read from the untrusted HEAD
# checkout strictly as YAML DATA (yq only — never executed, templated, or interpolated). The approval ROUTING
# (team-lead vs access-admin) is published separately by publish-verdict.sh; this script is the schema + refs
# backstop:
#   1. data hygiene  — no symlinks / multi-doc / oversize; metadata.name matches the filename
#   2. schema shape  — kind/apiVersion; required fields; no unknown keys; one reach per grant
#   3. ref integrity — every grant's role exists in the catalog (gitops/roles, #887) and the role's reach
#                       permits the grant's scope; every team grant targets an existing Team. Both from BASE.
#   4. anchor uniqueness — a Keycloak anchor (spec.person) maps to at most one Person
#
# Env in:
#   BASE_DIR, HEAD_DIR     the two checkouts
#   PEOPLE_FILES           space-separated added/modified gitops/people/*.yaml (relative)
#   PEOPLE_DELETED_FILES   space-separated removed/renamed-away Person files (relative)
#   REPORT_MD              output markdown body for the sticky comment
# Requires: yq (mikefarah).
# NOTE: -e is intentionally omitted — checks accumulate ALL failures and fail closed via the explicit exit.
set -uo pipefail

: "${BASE_DIR:?}" "${HEAD_DIR:?}" "${REPORT_MD:?}"
PEOPLE_FILES="${PEOPLE_FILES:-}"
PEOPLE_DELETED_FILES="${PEOPLE_DELETED_FILES:-}"

NAME_RE='^[a-z][a-z0-9-]{1,30}$'
ANCHOR_RE='^[a-zA-Z0-9._-]{1,64}$'   # a Keycloak username or sub — no PII, no '@' (email is never the anchor)
GH_LOGIN_RE='^[A-Za-z0-9-]{1,39}$'
VALID_SCOPES=" platform "
VALID_ACTIVATION=" on-demand "
TEAMS_DIR="${BASE_DIR}/gitops/teams"
ROLES_DIR="${BASE_DIR}/gitops/roles"   # the WorkforceRole catalog (#887) — grants reference these by name
PEOPLE_DIR_BASE="${BASE_DIR}/gitops/people"

in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

overall_rc=0
errors=()
note() { errors+=("$1"); echo "::error::people-gate: $1" >&2; overall_rc=1; }

anchors_tmp="$(mktemp)"  # "anchor<TAB>person-name" pairs across the post-merge roster — for uniqueness
trap 'rm -f "$anchors_tmp"' EXIT

# Set of files changing in this PR (added/modified + deleted), so the base sweep skips superseded versions.
changed_set=" ${PEOPLE_FILES} ${PEOPLE_DELETED_FILES} "

# ---------------------------------------------------------------------------------------------------
# Added / modified Person CRs (read from untrusted HEAD as data)
# ---------------------------------------------------------------------------------------------------
for pf in $PEOPLE_FILES; do
  f="${HEAD_DIR}/${pf}"
  base="$(basename "$pf")"
  person="${base%.yaml}"; person="${person%.yml}"
  echo "== validating ${pf} =="

  # --- data hygiene ---------------------------------------------------------------------------------
  if [ ! -f "$f" ]; then note "${pf}: missing from head checkout"; continue; fi
  if [ -L "$f" ]; then note "${pf}: symlinks are not allowed"; continue; fi
  if [ "$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")" -gt 8192 ]; then note "${pf}: exceeds 8KB"; continue; fi
  if [ "$(yq eval-all 'documentIndex' "$f" | tail -1)" != "0" ]; then note "${pf}: multi-document YAML is not allowed"; continue; fi

  # --- identity / kind ------------------------------------------------------------------------------
  [ "$(yq '.kind' "$f")" = "Person" ] || note "${pf}: kind must be Person"
  [ "$(yq '.apiVersion' "$f")" = "platform.refplat.org/v1beta1" ] || note "${pf}: apiVersion must be platform.refplat.org/v1beta1"
  metaname="$(yq '.metadata.name' "$f")"
  [[ "$metaname" =~ $NAME_RE ]] || note "${pf}: metadata.name '${metaname}' must match ${NAME_RE}"
  [ "$metaname" = "$person" ] || note "${pf}: metadata.name '${metaname}' must equal the filename '${person}'"

  # --- no unknown spec keys -------------------------------------------------------------------------
  for k in $(yq '.spec | keys | .[]' "$f" 2>/dev/null); do
    case "$k" in person | handles | grants) ;; *) note "${pf}: unknown spec key '${k}'";; esac
  done

  # --- anchor (spec.person) -------------------------------------------------------------------------
  anchor="$(yq '.spec.person // ""' "$f")"
  if [ -z "$anchor" ]; then
    note "${pf}: spec.person (the Keycloak anchor) is required"
  elif [[ ! "$anchor" =~ $ANCHOR_RE ]]; then
    note "${pf}: spec.person '${anchor}' must match ${ANCHOR_RE} (a Keycloak username/sub — never an email/PII)"
  else
    printf '%s\t%s\n' "$anchor" "$metaname" >>"$anchors_tmp"
  fi

  # --- handles (optional; only github, a valid login) -----------------------------------------------
  if [ "$(yq '.spec | has("handles")' "$f")" = "true" ]; then
    for k in $(yq '.spec.handles | keys | .[]' "$f" 2>/dev/null); do
      case "$k" in github) ;; *) note "${pf}: unknown spec.handles key '${k}' (only 'github' is a declared bootstrap handle; others are discovered, ADR-084)";; esac
    done
    gh_login="$(yq '.spec.handles.github // ""' "$f")"
    [ -z "$gh_login" ] || [[ "$gh_login" =~ $GH_LOGIN_RE ]] || note "${pf}: spec.handles.github '${gh_login}' is not a valid GitHub login"
  fi

  # --- grants ---------------------------------------------------------------------------------------
  ngrants="$(yq '.spec.grants | length' "$f" 2>/dev/null || echo 0)"
  if [ "$ngrants" -lt 1 ]; then
    note "${pf}: spec.grants must have ≥1 entry"
  fi
  i=0
  while [ "$i" -lt "$ngrants" ]; do
    g=".spec.grants[$i]"
    # no unknown grant keys
    for k in $(yq "${g} | keys | .[]" "$f" 2>/dev/null); do
      case "$k" in role | team | scope | activation) ;; *) note "${pf}: grant[${i}] unknown key '${k}'";; esac
    done
    role="$(yq "${g}.role // \"\"" "$f")"
    team="$(yq "${g}.team // \"\"" "$f")"
    scope="$(yq "${g}.scope // \"\"" "$f")"
    activation="$(yq "${g}.activation // \"\"" "$f")"

    [ -n "$role" ] || note "${pf}: grant[${i}].role is required"

    # role must exist as a real artifact in the catalog (gitops/roles, #887) — read its declared reach (trusted base)
    role_reach=""
    if [ -n "$role" ]; then
      rolefile="${ROLES_DIR}/${role}.yaml"; [ -f "$rolefile" ] || rolefile="${ROLES_DIR}/${role}.yml"
      if [ ! -f "$rolefile" ]; then
        note "${pf}: grant[${i}] role '${role}' does not exist in the catalog (gitops/roles/) — add the WorkforceRole first (#887)"
      else
        role_reach="$(yq '.spec.reach // ""' "$rolefile" 2>/dev/null)"
      fi
    fi

    # exactly one reach (team xor scope), and it must be one the role permits
    reach_count=0
    [ -n "$team" ] && reach_count=$((reach_count + 1))
    [ -n "$scope" ] && reach_count=$((reach_count + 1))
    if [ "$reach_count" -ne 1 ]; then
      note "${pf}: grant[${i}] must set exactly one of 'team' or 'scope' (got ${reach_count})"
    else
      if [ -n "$team" ]; then
        # team ref must exist in the trusted base team list
        if [ ! -f "${TEAMS_DIR}/${team}.yaml" ] && [ ! -f "${TEAMS_DIR}/${team}.yml" ]; then
          note "${pf}: grant[${i}] team '${team}' does not exist in gitops/teams/"
        fi
        # the role's reach must allow a team-scoped grant
        [ -z "$role_reach" ] || in_list "$role_reach" " team any " || note "${pf}: grant[${i}] role '${role}' (reach '${role_reach}') cannot be granted at team scope"
      else
        in_list "$scope" "$VALID_SCOPES" || note "${pf}: grant[${i}] scope '${scope}' not in {${VALID_SCOPES# }}"
        [ -z "$role_reach" ] || in_list "$role_reach" " platform any " || note "${pf}: grant[${i}] role '${role}' (reach '${role_reach}') cannot be granted at platform scope"
      fi
    fi

    [ -z "$activation" ] || in_list "$activation" "$VALID_ACTIVATION" || note "${pf}: grant[${i}].activation '${activation}' not in {${VALID_ACTIVATION# }}"
    i=$((i + 1))
  done

  echo "   ${pf}: checked"
done

# ---------------------------------------------------------------------------------------------------
# Anchor uniqueness — sweep the surviving BASE roster (skip files this PR changes/deletes), add to the
# head pairs collected above, then flag any anchor mapping to >1 distinct Person.
# ---------------------------------------------------------------------------------------------------
if [ -d "$PEOPLE_DIR_BASE" ]; then
  while IFS= read -r bf; do
    rel="gitops/people/$(basename "$bf")"
    case "$changed_set" in *" $rel "*) continue ;; esac      # superseded by head / being deleted
    [ "$(basename "$bf")" = "README.yaml" ] && continue
    a="$(yq '.spec.person // ""' "$bf" 2>/dev/null)"
    n="$(yq '.metadata.name // ""' "$bf" 2>/dev/null)"
    [ -n "$a" ] && [ -n "$n" ] && printf '%s\t%s\n' "$a" "$n" >>"$anchors_tmp"
  done < <(find "$PEOPLE_DIR_BASE" -type f \( -name '*.yaml' -o -name '*.yml' \))
fi
# anchors used by more than one distinct person name
while IFS= read -r dupe; do
  [ -n "$dupe" ] && note "spec.person anchor '${dupe}' is claimed by more than one Person — an anchor maps to exactly one human"
done < <(sort -u "$anchors_tmp" | awk -F'\t' '{c[$1]++} END {for (a in c) if (c[a] > 1) print a}')

# ---------------------------------------------------------------------------------------------------
# Sticky-comment report
# ---------------------------------------------------------------------------------------------------
{
  echo "<!-- people-gate -->"
  echo "## People gate — Person registry validation"
  echo
  n_changed="$(echo $PEOPLE_FILES | wc -w | tr -d ' ')"
  n_deleted="$(echo $PEOPLE_DELETED_FILES | wc -w | tr -d ' ')"
  echo "_Validates \`gitops/people\` changes (${n_changed} changed, ${n_deleted} removed): schema shape, the role catalog, team-ref integrity, and anchor uniqueness. Approval routing (team-lead vs access-admin) is the separate **People Approval** check._"
  echo
  if [ "$overall_rc" -eq 0 ]; then
    echo "### ✅ Passed"
    [ -n "${PEOPLE_FILES// /}" ] && { echo; echo "Validated:"; for pf in $PEOPLE_FILES; do echo "- \`${pf}\`"; done; }
    [ -n "${PEOPLE_DELETED_FILES// /}" ] && { echo; echo "Offboarded (removed):"; for pf in $PEOPLE_DELETED_FILES; do echo "- \`${pf}\`"; done; }
  else
    echo "### ❌ Failed — fix these before merge"
    echo
    for e in "${errors[@]}"; do echo "- ${e}"; done
  fi
  echo
  echo "---"
  echo "_Grant roles are validated against the \`gitops/roles\` catalog (#887): the role must exist and its reach must permit the grant's scope._"
} >"$REPORT_MD"

if [ "$overall_rc" -ne 0 ]; then
  echo "people-gate: validation FAILED (${#errors[@]} problem(s))" >&2
else
  echo "people-gate: all checks passed"
fi
exit "$overall_rc"
