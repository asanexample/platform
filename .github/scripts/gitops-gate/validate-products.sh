#!/usr/bin/env bash
# Product gate (#388) — validate gitops/products/**/*.yaml (the Product registry) on a PR. Schema shape +
# enums + ownership (mirrors the CRD restrict it would hit at admission). Read strictly as YAML DATA (yq only;
# never executed). Trusted inputs (the Team list, this script) come from the BASE checkout.
#
# Env in:
#   BASE_DIR             trusted base checkout (Team list, schema authority)
#   HEAD_DIR             untrusted PR head checkout (the Product files being validated)
#   PRODUCT_FILES        space-separated added/modified gitops/products/**/*.yaml (relative paths)
# Requires: yq (mikefarah).
set -uo pipefail
: "${BASE_DIR:?}" "${HEAD_DIR:?}"
PRODUCT_FILES="${PRODUCT_FILES:-}"

NAME_RE='^[a-z][a-z0-9-]{1,40}$'
VALID_TENANCY=" pooled per-customer "
VALID_COMPUTE=" shared-namespace dedicated-namespace dedicated-nodes dedicated-cluster dedicated-account "

rc=0
note() { echo "::error::product-gate: $1" >&2; rc=1; }

for rel in $PRODUCT_FILES; do
  f="${HEAD_DIR}/${rel}"
  pf="$rel"
  [ -f "$f" ] || { note "${pf}: missing from head checkout"; continue; }
  [ -L "$f" ] && { note "${pf}: symlinks not allowed"; continue; }

  # identity
  [ "$(yq '.kind' "$f")" = "Product" ] || note "${pf}: kind must be Product"
  [ "$(yq '.apiVersion' "$f")" = "platform.refplat.org/v1beta1" ] || note "${pf}: apiVersion must be platform.refplat.org/v1beta1"

  team="$(yq '.spec.team // ""' "$f")"
  repo="$(yq '.spec.repo // ""' "$f")"
  metaname="$(yq '.metadata.name // ""' "$f")"
  # path is load-bearing: gitops/products/<team>/<filename>.yaml. filename stem = product short name;
  # metadata.name = <team>-<product>; the directory = <team>. A path/content mismatch syncs nowhere coherent.
  short="$(basename "$rel" .yaml)"
  dir_team="$(basename "$(dirname "$rel")")"
  [ "$dir_team" = "$team" ] || note "${pf}: directory '${dir_team}/' must equal spec.team '${team}' (gitops/products/<team>/<product>.yaml)"

  # required + shape
  [ -n "$team" ] || note "${pf}: spec.team is required"
  [ -n "$repo" ] || note "${pf}: spec.repo is required"
  [[ "$metaname" =~ $NAME_RE ]] || note "${pf}: metadata.name '${metaname}' must match ${NAME_RE}"
  [ "$metaname" = "${team}-${short}" ] || note "${pf}: metadata.name '${metaname}' must equal '<spec.team>-<filename>' = '${team}-${short}'"
  [[ "$repo" == */* ]] || note "${pf}: spec.repo '${repo}' must be 'owner/repo'"

  # enums
  tenancy="$(yq '.spec.tenancy // "pooled"' "$f")"
  [[ "$VALID_TENANCY" == *" $tenancy "* ]] || note "${pf}: spec.tenancy '${tenancy}' not in {pooled, per-customer}"
  comp="$(yq '.spec.defaultIsolation.compute // ""' "$f")"
  [ -z "$comp" ] || [[ "$VALID_COMPUTE" == *" $comp "* ]] || note "${pf}: defaultIsolation.compute '${comp}' not in the isolation ladder"

  # no unknown spec keys (the CRD prunes them silently → a typo would vanish)
  for k in $(yq '.spec | keys | .[]' "$f" 2>/dev/null); do
    case "$k" in team | repo | tenancy | defaultIsolation | restrictWithinTeam | domains | displayName | roles) ;;
      *) note "${pf}: unknown spec key '${k}' (typo? it would be silently dropped)";; esac
  done

  # release-approver override (ADR-068 §7, #501): if present, a non-empty list of valid GitHub logins (an empty
  # override would silently fall through to the Team default — forbid it; omit the block to inherit). The login
  # rule (no brackets) already excludes App bots like `…[bot]`, which must never be release-approvers.
  if [ "$(yq '(.spec.roles | has("releaseApprover")) // false' "$f" 2>/dev/null)" = "true" ]; then
    n="$(yq '.spec.roles.releaseApprover | length' "$f" 2>/dev/null || echo 0)"
    [ "$n" -ge 1 ] || note "${pf}: spec.roles.releaseApprover is empty — omit the block to inherit the Team default"
    while IFS= read -r login; do
      [ -z "$login" ] && continue
      [[ "$login" =~ ^[A-Za-z0-9-]{1,39}$ ]] || note "${pf}: release-approver '${login}' is not a valid GitHub login"
    done < <(yq -r '(.spec.roles.releaseApprover // [])[]' "$f" 2>/dev/null)
  fi

  # ownership: the owning Team must exist in the trusted base (its envelope is knowable at admission).
  [ -f "${BASE_DIR}/gitops/teams/${team}.yaml" ] || note "${pf}: spec.team '${team}' has no gitops/teams/${team}.yaml — a Product must be owned by an existing Team"

  echo "   ${pf}: checked"
done

exit $rc
