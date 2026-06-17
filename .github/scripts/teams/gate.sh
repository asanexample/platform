#!/usr/bin/env bash
# Teams Gate — validate Team-envelope PRs (gitops/teams/**) before merge (sibling of the Tenant Claims Gate).
#
# SECURITY MODEL (mirrors tenant-claims-gate): this script + everything authoritative (the Team CRD schema)
# is read from the TRUSTED BASE checkout. The PR's Team CRs are read from the untrusted HEAD checkout strictly
# as YAML DATA (yq only — never executed, templated, or interpolated). Teams are deliberately HUMAN-reviewed
# (CODEOWNERS), so this gate is NOT an automerge arm; it's the automated guardrail a reviewer can't eyeball:
#   1. data hygiene   — no symlinks / multi-doc / oversize; metadata.name matches the filename
#   2. schema shape   — required fields present; allowedTiers/allowedStages within the CRD enums; no
#                       unknown keys (the CRD prunes them silently at admission → a typo would vanish)
#   3. envelope deny-set (the security core) — the CRD does NOT bound quotaCap / maxDedicatedIsolation / ssoGroup,
#                       so an over-permissive or privileged-group envelope would pass admission unflagged.
#   4. deletion guard — a Team CR removal yanks an envelope out from under its environments; deny while any
#                       Environment still references the team.
#
# Env in:
#   BASE_DIR, HEAD_DIR        the two checkouts
#   TEAM_FILES                space-separated added/modified gitops/teams/*.yaml (relative)
#   TEAM_DELETED_FILES        space-separated removed/renamed-away team files (relative)
#   REPORT_MD                 output markdown body for the sticky comment
#   MAX_QUOTA_CPU             per-tenant cpu ceiling the envelope may grant   (default 64)
#   MAX_QUOTA_MEMORY          per-tenant memory ceiling                       (default 256Gi)
#   MAX_QUOTA_PODS            per-tenant pods ceiling                         (default 500)
#   MAX_DEDICATED_ISOLATION   envelope.maxDedicatedIsolation.{cluster,account} ceiling (default 0 — pooled only)
#   MAX_RESOURCES_PER_ENV     envelope.resources.maxPerEnvironment ceiling (ADR-073; default 25)
#   DENIED_SSO_GROUPS         space/comma-separated privileged groups a team may NOT map to (default platform-admins)
# Requires: yq (mikefarah), python3.
set -uo pipefail

: "${BASE_DIR:?}" "${HEAD_DIR:?}" "${REPORT_MD:?}"
TEAM_FILES="${TEAM_FILES:-}"
TEAM_DELETED_FILES="${TEAM_DELETED_FILES:-}"
MAX_QUOTA_CPU="${MAX_QUOTA_CPU:-64}"
MAX_QUOTA_MEMORY="${MAX_QUOTA_MEMORY:-256Gi}"
MAX_QUOTA_PODS="${MAX_QUOTA_PODS:-500}"
MAX_DEDICATED_ISOLATION="${MAX_DEDICATED_ISOLATION:-0}"
MAX_RESOURCES_PER_ENV="${MAX_RESOURCES_PER_ENV:-25}"
DENIED_SSO_GROUPS="${DENIED_SSO_GROUPS:-platform-admins}"

NAME_RE='^[a-z][a-z0-9-]{1,30}$'
VALID_TIERS=" standard elevated pci hipaa "
VALID_STAGES=" dev test uat staging prod "
VALID_ENGINES=" s3 sqs "
ENVIRONMENTS_DIR="${BASE_DIR}/gitops/environments"

overall_rc=0
errors=()      # human-readable failures (also emitted as ::error:: annotations)
note() { errors+=("$1"); echo "::error::teams-gate: $1" >&2; overall_rc=1; }

# quantity comparison: qty_le <value> <cap> <cpu|memory|int> → exit 0 if value <= cap
qty_le() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys, re
val, cap, kind = sys.argv[1], sys.argv[2], sys.argv[3]
def cpu(s):
    s = str(s).strip()
    return float(s[:-1]) if s.endswith('m') else float(s) * 1000.0
def mem(s):
    s = str(s).strip()
    u = {'Ki':2**10,'Mi':2**20,'Gi':2**30,'Ti':2**40,'Pi':2**50,'Ei':2**60,
         'K':1e3,'M':1e6,'G':1e9,'T':1e12,'P':1e15,'E':1e18}
    m = re.match(r'^([0-9.]+)\s*([A-Za-z]*)$', s)
    if not m: sys.exit(2)
    return float(m.group(1)) * u.get(m.group(2), 1)
fn = {'cpu': cpu, 'memory': mem, 'int': lambda x: float(x)}[kind]
try:
    sys.exit(0 if fn(val) <= fn(cap) else 1)
except Exception:
    sys.exit(2)
PY
}

# ---------------------------------------------------------------------------------------------------
# Added / modified Team CRs (read from untrusted HEAD as data)
# ---------------------------------------------------------------------------------------------------
for tf in $TEAM_FILES; do
  f="${HEAD_DIR}/${tf}"
  base="$(basename "$tf")"
  team="${base%.yaml}"
  team="${team%.yml}"
  echo "== validating ${tf} =="

  # --- data hygiene ---------------------------------------------------------------------------------
  if [ ! -f "$f" ]; then note "${tf}: missing from head checkout"; continue; fi
  if [ -L "$f" ]; then note "${tf}: symlinks are not allowed"; continue; fi
  if [ "$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")" -gt 16384 ]; then note "${tf}: exceeds 16KB"; continue; fi
  if [ "$(yq eval-all 'documentIndex' "$f" | tail -1)" != "0" ]; then note "${tf}: multi-document YAML is not allowed"; continue; fi

  # --- identity / kind ------------------------------------------------------------------------------
  [ "$(yq '.kind' "$f")" = "Team" ] || note "${tf}: kind must be Team"
  [ "$(yq '.apiVersion' "$f")" = "platform.refplat.org/v1beta1" ] || note "${tf}: apiVersion must be platform.refplat.org/v1beta1"
  metaname="$(yq '.metadata.name' "$f")"
  [[ "$metaname" =~ $NAME_RE ]] || note "${tf}: metadata.name '${metaname}' must match ${NAME_RE}"
  [ "$metaname" = "$team" ] || note "${tf}: metadata.name '${metaname}' must equal the filename '${team}'"

  # --- no unknown keys (the CRD prunes them silently at admission) -----------------------------------
  for k in $(yq '.spec | keys | .[]' "$f" 2>/dev/null); do
    case "$k" in ssoGroup | envelope | roles) ;; *) note "${tf}: unknown spec key '${k}' (typo? it would be silently dropped)";; esac
  done

  # --- release-approver set (ADR-068 §7, #501): if present, a non-empty list of valid GitHub logins. This is the
  # team-wide default prod approver set; editing it requires a second-person approval (the Teams Approval gate). --
  if [ "$(yq '(.spec.roles | has("releaseApprover")) // false' "$f" 2>/dev/null)" = "true" ]; then
    [ "$(yq '.spec.roles.releaseApprover | length' "$f" 2>/dev/null || echo 0)" -ge 1 ] || note "${tf}: spec.roles.releaseApprover is empty — omit it, or list ≥1 GitHub login"
    while IFS= read -r login; do
      [ -z "$login" ] && continue
      [[ "$login" =~ ^[A-Za-z0-9-]{1,39}$ ]] || note "${tf}: release-approver '${login}' is not a valid GitHub login"
    done < <(yq -r '(.spec.roles.releaseApprover // [])[]' "$f" 2>/dev/null)
  fi
  for k in $(yq '.spec.envelope | keys | .[]' "$f" 2>/dev/null); do
    case "$k" in allowedTiers | allowedStages | allowedLocations | quotaCap | maxDedicatedIsolation | maxCrossTeamGrantsPerProduct | resources) ;; *) note "${tf}: unknown spec.envelope key '${k}'";; esac
  done

  # --- required fields ------------------------------------------------------------------------------
  sso="$(yq '.spec.ssoGroup // ""' "$f")"
  [ -n "$sso" ] || note "${tf}: spec.ssoGroup is required"
  [ "$(yq '.spec.envelope.allowedTiers | length' "$f" 2>/dev/null || echo 0)" -ge 1 ] || note "${tf}: spec.envelope.allowedTiers must have ≥1 entry"
  [ "$(yq '.spec.envelope.allowedStages | length' "$f" 2>/dev/null || echo 0)" -ge 1 ] || note "${tf}: spec.envelope.allowedStages must have ≥1 entry"
  [ "$(yq '.spec.envelope | has("quotaCap")' "$f")" = "true" ] || note "${tf}: spec.envelope.quotaCap is required"

  # --- enum bounds (mirror the CRD enums) -----------------------------------------------------------
  for t in $(yq '.spec.envelope.allowedTiers[]' "$f" 2>/dev/null); do
    [[ "$VALID_TIERS" == *" $t "* ]] || note "${tf}: allowedTiers '${t}' not in {standard,elevated,pci,hipaa}"
  done
  for e in $(yq '.spec.envelope.allowedStages[]' "$f" 2>/dev/null); do
    [[ "$VALID_STAGES" == *" $e "* ]] || note "${tf}: allowedStages '${e}' not in {dev,test,uat,staging,prod}"
  done

  # --- envelope deny-set (the CRD does NOT bound these) ---------------------------------------------
  # ssoGroup must not be a privileged/platform group (case-insensitive)
  sso_lc="$(printf '%s' "$sso" | tr '[:upper:]' '[:lower:]')"
  for g in ${DENIED_SSO_GROUPS//,/ }; do
    [ "$sso_lc" = "$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')" ] && note "${tf}: spec.ssoGroup '${sso}' is a denied privileged group — a Team may not map to it"
  done
  # quotaCap ceilings
  cpu="$(yq '.spec.envelope.quotaCap.cpu // ""' "$f")"
  mem="$(yq '.spec.envelope.quotaCap.memory // ""' "$f")"
  pods="$(yq '.spec.envelope.quotaCap.pods // ""' "$f")"
  [ -z "$cpu" ] || qty_le "$cpu" "$MAX_QUOTA_CPU" cpu || note "${tf}: quotaCap.cpu '${cpu}' exceeds the platform max ${MAX_QUOTA_CPU}"
  [ -z "$mem" ] || qty_le "$mem" "$MAX_QUOTA_MEMORY" memory || note "${tf}: quotaCap.memory '${mem}' exceeds the platform max ${MAX_QUOTA_MEMORY}"
  [ -z "$pods" ] || qty_le "$pods" "$MAX_QUOTA_PODS" int || note "${tf}: quotaCap.pods '${pods}' exceeds the platform max ${MAX_QUOTA_PODS}"
  # maxDedicatedIsolation ceiling (cluster + account dials — both platform-gated)
  mdc="$(yq '.spec.envelope.maxDedicatedIsolation.cluster // 0' "$f")"
  mda="$(yq '.spec.envelope.maxDedicatedIsolation.account // 0' "$f")"
  qty_le "$mdc" "$MAX_DEDICATED_ISOLATION" int || note "${tf}: maxDedicatedIsolation.cluster '${mdc}' exceeds the allowed max ${MAX_DEDICATED_ISOLATION} (dedicated isolation is platform-gated)"
  qty_le "$mda" "$MAX_DEDICATED_ISOLATION" int || note "${tf}: maxDedicatedIsolation.account '${mda}' exceeds the allowed max ${MAX_DEDICATED_ISOLATION} (dedicated isolation is platform-gated)"
  # self-service resources envelope (ADR-073): the CRD enums allowedEngines + isolationFloor but does NOT bound
  # maxPerEnvironment — cap it (cost backstop). allowedEngines must be platform-known engines.
  if [ "$(yq '.spec.envelope | has("resources")' "$f")" = "true" ]; then
    for eng in $(yq '.spec.envelope.resources.allowedEngines[]' "$f" 2>/dev/null); do
      [[ "$VALID_ENGINES" == *" $eng "* ]] || note "${tf}: envelope.resources.allowedEngines '${eng}' not in {${VALID_ENGINES# }}"
    done
    rmax="$(yq '.spec.envelope.resources.maxPerEnvironment // 0' "$f")"
    qty_le "$rmax" "$MAX_RESOURCES_PER_ENV" int || note "${tf}: envelope.resources.maxPerEnvironment '${rmax}' exceeds the platform max ${MAX_RESOURCES_PER_ENV}"
    rfloor="$(yq '.spec.envelope.resources.isolationFloor // "shared"' "$f")"
    case "$rfloor" in shared | dedicated) ;; *) note "${tf}: envelope.resources.isolationFloor '${rfloor}' not in {shared,dedicated}";; esac
  fi

  echo "   ${tf}: checked"
done

# ---------------------------------------------------------------------------------------------------
# Deletions (read the still-present file from BASE; deny while tenants reference the team)
# ---------------------------------------------------------------------------------------------------
for tf in $TEAM_DELETED_FILES; do
  f="${BASE_DIR}/${tf}"
  base="$(basename "$tf")"; team="${base%.yaml}"; team="${team%.yml}"
  [ -f "$f" ] || continue
  refs=0
  if [ -d "$ENVIRONMENTS_DIR" ]; then
    while IFS= read -r env; do
      [ "$(yq '.spec.team // ""' "$env" 2>/dev/null)" = "$team" ] && refs=$((refs + 1))
    done < <(find "$ENVIRONMENTS_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \))
  fi
  if [ "$refs" -gt 0 ]; then
    note "${tf}: cannot delete Team '${team}' — ${refs} Environment(s) still reference it. Decommission those Environments before removing the team."
  else
    echo "   ${tf}: no referencing Environments — delete permitted"
  fi
done

# ---------------------------------------------------------------------------------------------------
# Sticky-comment report
# ---------------------------------------------------------------------------------------------------
{
  echo "<!-- teams-gate -->"
  echo "## Teams gate — Team envelope validation"
  echo
  n_changed="$(echo $TEAM_FILES | wc -w | tr -d ' ')"
  n_deleted="$(echo $TEAM_DELETED_FILES | wc -w | tr -d ' ')"
  echo "_Validates \`gitops/teams\` changes (${n_changed} changed, ${n_deleted} removed): schema shape, enum bounds, the envelope escalation deny-set, and the deletion guard. Teams stay human-reviewed (CODEOWNERS); this is the automated backstop._"
  echo
  if [ "$overall_rc" -eq 0 ]; then
    echo "### ✅ Passed"
    [ -n "${TEAM_FILES// /}" ] && { echo; echo "Validated:"; for tf in $TEAM_FILES; do echo "- \`${tf}\`"; done; }
    [ -n "${TEAM_DELETED_FILES// /}" ] && { echo; echo "Deletions permitted:"; for tf in $TEAM_DELETED_FILES; do echo "- \`${tf}\`"; done; }
  else
    echo "### ❌ Failed — fix these before merge"
    echo
    for e in "${errors[@]}"; do echo "- ${e}"; done
  fi
  echo
  echo "---"
  echo "_Deny-set: quotaCap ≤ cpu \`${MAX_QUOTA_CPU}\` / mem \`${MAX_QUOTA_MEMORY}\` / pods \`${MAX_QUOTA_PODS}\`, maxDedicatedIsolation ≤ \`${MAX_DEDICATED_ISOLATION}\`, resources.maxPerEnvironment ≤ \`${MAX_RESOURCES_PER_ENV}\` (engines ⊆ {\`${VALID_ENGINES# }\`}), ssoGroup ∉ {\`${DENIED_SSO_GROUPS}\`}._"
} >"$REPORT_MD"

if [ "$overall_rc" -ne 0 ]; then
  echo "teams-gate: validation FAILED (${#errors[@]} problem(s))" >&2
else
  echo "teams-gate: all checks passed"
fi
exit "$overall_rc"
