#!/usr/bin/env bash
# ServiceGrant gate (ADR-101) — validate gitops/grants/**/*.yaml on a PR. This directory holds BOTH kinds: the
# pre-existing AccessGrant (ADR-068, human RBAC — untouched, out of scope here) and the new ServiceGrant
# (ADR-101, a governed cross-team NETWORK capability) — only ServiceGrant entries are checked; an AccessGrant
# file is a silent no-op. The SHIFT-LEFT of the Kyverno restrict-service-grant-admission /
# restrict-environment-dependencies admission policies: schema shape, the load-bearing directory-team ==
# spec.target.team authorization check (the grantor/producer owns the directory + the PR — adapted from
# validate-environments.sh's dir_team == spec.team, but keyed off target.team since the producer is the one
# consenting, not the consumer), both sides' owning Product exists, and the regulated-tier (hipaa/pci)
# exclusion — run pre-merge so a bad grant fails the PR instead of being rejected at admission. Read strictly
# as YAML DATA (yq only). Products/Environments may be added by the same PR, so they are read from head first,
# falling back to base (like validate-environments.sh).
#
# Env in:
#   BASE_DIR      trusted base checkout
#   HEAD_DIR      untrusted PR head checkout (the ServiceGrant + Product + Environment files)
#   GRANT_FILES   space-separated added/modified gitops/grants/**/*.yaml (relative)
# Requires: yq (mikefarah).
set -uo pipefail
: "${BASE_DIR:?}" "${HEAD_DIR:?}"
GRANT_FILES="${GRANT_FILES:-}"

rc=0
note() { echo "::error::service-grant-gate: $1" >&2; rc=1; }

# env_tier <team> <product> <stage> — resolves the tier a SPECIFIC Environment actually runs at. Neither the
# Team nor Product registry carries a single tier (Team.envelope.allowedTiers is only the SET a Team may use
# across all its Environments); the concrete tier for one {team,product,stage} lives on that stage's own
# XEnvironment claim (gitops/environments/<team>/<product>/<stage>.yaml, spec.tier). Prefers head (the claim may
# land in the same PR), falls back to base. Echoes "" if the claim doesn't exist yet — NOT an error: a
# ServiceGrant may legitimately be authored slightly ahead of (or independent of) the exact claim file, so this
# is a best-effort regulated-tier check, not an existence check.
env_tier() {
  local team="$1" product="$2" stage="$3" f
  f="${HEAD_DIR}/gitops/environments/${team}/${product}/${stage}.yaml"
  [ -f "$f" ] || f="${BASE_DIR}/gitops/environments/${team}/${product}/${stage}.yaml"
  [ -f "$f" ] || { echo ""; return; }
  yq -r '.spec.tier // "standard"' "$f"
}

for rel in $GRANT_FILES; do
  case "$rel" in */README.md) continue;; esac
  f="${HEAD_DIR}/${rel}"
  pf="$rel"
  [ -f "$f" ] || { note "${pf}: missing from head checkout"; continue; }
  [ -L "$f" ] && { note "${pf}: symlinks not allowed"; continue; }

  kind="$(yq -r '.kind // ""' "$f")"
  case "$kind" in
    AccessGrant) continue ;;   # pre-existing human-RBAC kind (ADR-068) — out of scope for this gate
    ServiceGrant) ;;           # checked below
    *) note "${pf}: kind must be ServiceGrant or AccessGrant, got '${kind:-<unset>}'"; continue ;;
  esac

  # --- required fields ---
  t_team="$(yq -r '.spec.target.team // ""' "$f")"
  t_product="$(yq -r '.spec.target.product // ""' "$f")"
  t_stage="$(yq -r '.spec.target.stage // ""' "$f")"
  t_service="$(yq -r '.spec.target.service // ""' "$f")"
  s_team="$(yq -r '.spec.subject.team // ""' "$f")"
  s_product="$(yq -r '.spec.subject.product // ""' "$f")"
  s_stage="$(yq -r '.spec.subject.stage // ""' "$f")"
  s_service="$(yq -r '.spec.subject.service // ""' "$f")"
  [ -n "$t_team" ]    || note "${pf}: spec.target.team is required"
  [ -n "$t_product" ] || note "${pf}: spec.target.product is required"
  [ -n "$t_stage" ]   || note "${pf}: spec.target.stage is required"
  [ -n "$t_service" ] || note "${pf}: spec.target.service is required"
  [ -n "$s_team" ]    || note "${pf}: spec.subject.team is required"
  [ -n "$s_product" ] || note "${pf}: spec.subject.product is required"
  [ -n "$s_stage" ]   || note "${pf}: spec.subject.stage is required"
  [ -n "$s_service" ] || note "${pf}: spec.subject.service is required"

  protocol="$(yq -r '.spec.capability.network.protocol // ""' "$f")"
  [ -n "$protocol" ] || note "${pf}: spec.capability.network.protocol is required"
  nports="$(yq -r '(.spec.capability.network.ports // []) | length' "$f")"
  { [ -n "$nports" ] && [ "$nports" -gt 0 ]; } 2>/dev/null || note "${pf}: spec.capability.network.ports must be a non-empty array"

  # --- directory-team authorization: the grantor (target.team) owns the directory + the PR (the load-bearing
  #     check — mirrors validate-environments.sh's dir_team == spec.team, keyed off target instead of the
  #     claim's own team since here the PRODUCER, not the resource's own owner, is consenting) ---
  dir_team="$(basename "$(dirname "$rel")")"
  if [ -n "$t_team" ] && [ "$dir_team" != "$t_team" ]; then
    note "${pf}: directory team '${dir_team}' must equal spec.target.team '${t_team}' (the grantor/producer owns the directory — gitops/grants/<target.team>/<name>.yaml)"
  fi

  # --- both sides' owning Product must exist (head, as data — a new Product may land in the same PR) ---
  if [ -n "$t_team" ] && [ -n "$t_product" ]; then
    tprod="${HEAD_DIR}/gitops/products/${t_team}/${t_product}.yaml"
    [ -f "$tprod" ] || tprod="${BASE_DIR}/gitops/products/${t_team}/${t_product}.yaml"
    [ -f "$tprod" ] || note "${pf}: target Product gitops/products/${t_team}/${t_product}.yaml not found"
  fi
  if [ -n "$s_team" ] && [ -n "$s_product" ]; then
    sprod="${HEAD_DIR}/gitops/products/${s_team}/${s_product}.yaml"
    [ -f "$sprod" ] || sprod="${BASE_DIR}/gitops/products/${s_team}/${s_product}.yaml"
    [ -f "$sprod" ] || note "${pf}: subject Product gitops/products/${s_team}/${s_product}.yaml not found"
  fi

  # --- regulated-tier exclusion: neither side's actual Environment (tier lives THERE, not on Team/Product —
  #     see env_tier above) may be hipaa/pci. Fast git-level feedback paired with the Kyverno admission-time
  #     backstop (restrict-service-grant-admission, service-grant-policies chart). ---
  if [ -n "$t_team" ] && [ -n "$t_product" ] && [ -n "$t_stage" ]; then
    ttier="$(env_tier "$t_team" "$t_product" "$t_stage")"
    case "$ttier" in
      hipaa|pci) note "${pf}: target ${t_team}/${t_product}/${t_stage} is tier '${ttier}' — regulated-tier Environments are excluded from ServiceGrant by default" ;;
    esac
  fi
  if [ -n "$s_team" ] && [ -n "$s_product" ] && [ -n "$s_stage" ]; then
    stier="$(env_tier "$s_team" "$s_product" "$s_stage")"
    case "$stier" in
      hipaa|pci) note "${pf}: subject ${s_team}/${s_product}/${s_stage} is tier '${stier}' — regulated-tier Environments are excluded from ServiceGrant by default" ;;
    esac
  fi

  echo "   ${pf}: checked"
done

exit $rc
