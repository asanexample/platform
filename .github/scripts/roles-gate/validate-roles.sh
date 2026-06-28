#!/usr/bin/env bash
# Roles Gate — validate WorkforceRole catalog PRs (gitops/roles/**) before merge (sibling of the Teams/People
# gates). The catalog is what Person grants reference and the #888/#889 generators project, so a role is a
# real, schema-checked artifact. Reads authoritative inputs from the TRUSTED BASE; the PR's role CRs from the
# untrusted HEAD strictly as YAML DATA (yq only).
#   1. data hygiene  — no symlinks / multi-doc / oversize; metadata.name matches the filename
#   2. schema shape  — kind/apiVersion; reach/power/mode/riskTier enums; required description; projection shape
#   3. deletion guard — deny removing a role while any Person grant still references it
#   4. BLAST RADIUS (§3.6 meta-governance) — report how many Person grants reference each changed role; the
#                      approval routing (admin two-person control) is published by publish-verdict.sh.
#
# Env in:
#   BASE_DIR, HEAD_DIR     the two checkouts
#   ROLE_FILES             space-separated added/modified gitops/roles/*.yaml (relative)
#   ROLE_DELETED_FILES     space-separated removed/renamed-away role files (relative)
#   REPORT_MD              output markdown body for the sticky comment
# Requires: yq (mikefarah).
# NOTE: -e intentionally omitted — accumulate ALL failures, fail closed via the explicit exit.
set -uo pipefail

: "${BASE_DIR:?}" "${HEAD_DIR:?}" "${REPORT_MD:?}"
ROLE_FILES="${ROLE_FILES:-}"
ROLE_DELETED_FILES="${ROLE_DELETED_FILES:-}"

NAME_RE='^[a-z][a-z0-9-]{1,30}$'
DURATION_RE='^PT([0-9]+H)?([0-9]+M)?([0-9]+S)?$'
VALID_REACH=" team platform any "
VALID_POWER=" look operate change manage-access "
VALID_MODE=" standing on-demand "
VALID_RISK=" standard elevated apex "
PEOPLE_DIR_BASE="${BASE_DIR}/gitops/people"

in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

overall_rc=0
errors=()
note() { errors+=("$1"); echo "::error::roles-gate: $1" >&2; overall_rc=1; }

# Count Person grants in the BASE roster that reference a given role name (the blast radius).
blast_radius() { # <role>
  local role="$1" n=0
  [ -d "$PEOPLE_DIR_BASE" ] || { echo 0; return; }
  while IFS= read -r pf; do
    [ "$(basename "$pf")" = "README.yaml" ] && continue
    local c
    c="$(yq "[.spec.grants[]? | select(.role == \"${role}\")] | length" "$pf" 2>/dev/null || echo 0)"
    n=$((n + c))
  done < <(find "$PEOPLE_DIR_BASE" -type f \( -name '*.yaml' -o -name '*.yml' \))
  echo "$n"
}

# ---------------------------------------------------------------------------------------------------
# Added / modified WorkforceRole CRs (read from untrusted HEAD as data)
# ---------------------------------------------------------------------------------------------------
declare -a radius_report=()
for rf in $ROLE_FILES; do
  f="${HEAD_DIR}/${rf}"
  base="$(basename "$rf")"; role="${base%.yaml}"; role="${role%.yml}"
  echo "== validating ${rf} =="

  if [ ! -f "$f" ]; then note "${rf}: missing from head checkout"; continue; fi
  if [ -L "$f" ]; then note "${rf}: symlinks are not allowed"; continue; fi
  if [ "$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")" -gt 8192 ]; then note "${rf}: exceeds 8KB"; continue; fi
  if [ "$(yq eval-all 'documentIndex' "$f" | tail -1)" != "0" ]; then note "${rf}: multi-document YAML is not allowed"; continue; fi

  [ "$(yq '.kind' "$f")" = "WorkforceRole" ] || note "${rf}: kind must be WorkforceRole"
  [ "$(yq '.apiVersion' "$f")" = "platform.refplat.org/v1beta1" ] || note "${rf}: apiVersion must be platform.refplat.org/v1beta1"
  metaname="$(yq '.metadata.name' "$f")"
  [[ "$metaname" =~ $NAME_RE ]] || note "${rf}: metadata.name '${metaname}' must match ${NAME_RE}"
  [ "$metaname" = "$role" ] || note "${rf}: metadata.name '${metaname}' must equal the filename '${role}'"

  for k in $(yq '.spec | keys | .[]' "$f" 2>/dev/null); do
    case "$k" in reach | power | mode | riskTier | description | identityCenter | keycloak) ;; *) note "${rf}: unknown spec key '${k}'";; esac
  done

  reach="$(yq '.spec.reach // ""' "$f")"
  power="$(yq '.spec.power // ""' "$f")"
  mode="$(yq '.spec.mode // ""' "$f")"
  risk="$(yq '.spec.riskTier // ""' "$f")"
  desc="$(yq '.spec.description // ""' "$f")"
  in_list "$reach" "$VALID_REACH" || note "${rf}: spec.reach '${reach}' not in {${VALID_REACH# }}"
  in_list "$power" "$VALID_POWER" || note "${rf}: spec.power '${power}' not in {${VALID_POWER# }}"
  in_list "$mode" "$VALID_MODE" || note "${rf}: spec.mode '${mode}' not in {${VALID_MODE# }}"
  in_list "$risk" "$VALID_RISK" || note "${rf}: spec.riskTier '${risk}' not in {${VALID_RISK# }}"
  [ -n "$desc" ] || note "${rf}: spec.description is required"

  # --- identityCenter projection (optional) ---------------------------------------------------------
  if [ "$(yq '.spec | has("identityCenter")' "$f")" = "true" ]; then
    for k in $(yq '.spec.identityCenter | keys | .[]' "$f" 2>/dev/null); do
      case "$k" in perTeam | permissionSet | sessionDuration | managedPolicies | inlinePolicy | note) ;; *) note "${rf}: unknown spec.identityCenter key '${k}'";; esac
    done
    ps="$(yq '.spec.identityCenter.permissionSet // ""' "$f")"
    [ -n "$ps" ] || note "${rf}: spec.identityCenter.permissionSet is required when identityCenter is set"
    sd="$(yq '.spec.identityCenter.sessionDuration // ""' "$f")"
    [ -z "$sd" ] || [[ "$sd" =~ $DURATION_RE ]] || note "${rf}: spec.identityCenter.sessionDuration '${sd}' is not an ISO-8601 duration (e.g. PT4H)"
  fi

  # --- keycloak projection (optional) ---------------------------------------------------------------
  if [ "$(yq '.spec | has("keycloak")' "$f")" = "true" ]; then
    for k in $(yq '.spec.keycloak | keys | .[]' "$f" 2>/dev/null); do
      case "$k" in realmRole | perTeamGroup | group) ;; *) note "${rf}: unknown spec.keycloak key '${k}'";; esac
    done
    [ -n "$(yq '.spec.keycloak.realmRole // ""' "$f")" ] || note "${rf}: spec.keycloak.realmRole is required when keycloak is set"
  fi

  radius_report+=("${role}=$(blast_radius "$role")")
  echo "   ${rf}: checked"
done

# ---------------------------------------------------------------------------------------------------
# Deletions — deny removing a role while any Person grant still references it (read from BASE).
# ---------------------------------------------------------------------------------------------------
for rf in $ROLE_DELETED_FILES; do
  base="$(basename "$rf")"; role="${base%.yaml}"; role="${role%.yml}"
  refs="$(blast_radius "$role")"
  if [ "$refs" -gt 0 ]; then
    note "${rf}: cannot delete role '${role}' — ${refs} Person grant(s) still reference it. Remove those grants first."
  else
    echo "   ${rf}: no referencing grants — delete permitted"
  fi
done

# ---------------------------------------------------------------------------------------------------
# Sticky-comment report (with the blast radius — §3.6 meta-governance)
# ---------------------------------------------------------------------------------------------------
{
  echo "<!-- roles-gate -->"
  echo "## Roles gate — workforce role catalog validation"
  echo
  n_changed="$(echo $ROLE_FILES | wc -w | tr -d ' ')"
  n_deleted="$(echo $ROLE_DELETED_FILES | wc -w | tr -d ' ')"
  echo "_Validates \`gitops/roles\` changes (${n_changed} changed, ${n_deleted} removed): schema shape, reach/power/mode/risk enums, the projection mappings, and the deletion guard. **Changing a role re-permissions everyone who holds it** — the approval is the separate **Roles Approval** check._"
  echo
  if [ "${#radius_report[@]}" -gt 0 ]; then
    echo "**Blast radius** (Person grants referencing each changed role, in the current roster):"
    echo
    for r in "${radius_report[@]}"; do echo "- \`${r%%=*}\` → **${r##*=}** grant(s)"; done
    echo
  fi
  if [ "$overall_rc" -eq 0 ]; then
    echo "### ✅ Passed"
    [ -n "${ROLE_DELETED_FILES// /}" ] && { echo; echo "Deletions permitted:"; for rf in $ROLE_DELETED_FILES; do echo "- \`${rf}\`"; done; }
  else
    echo "### ❌ Failed — fix these before merge"
    echo
    for e in "${errors[@]}"; do echo "- ${e}"; done
  fi
} >"$REPORT_MD"

if [ "$overall_rc" -ne 0 ]; then
  echo "roles-gate: validation FAILED (${#errors[@]} problem(s))" >&2
else
  echo "roles-gate: all checks passed"
fi
exit "$overall_rc"
