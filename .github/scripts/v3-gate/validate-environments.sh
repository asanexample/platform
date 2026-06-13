#!/usr/bin/env bash
# v3 Environment gate (#388) — validate gitops/environments/**/*.yaml (XEnvironment claims) on a PR. Schema +
# enums + the envelope SHIFT-LEFT (the same checks restrict-environment-envelope (#387) makes at admission, run
# pre-merge against the projected Team + Product): stage/tier ∈ envelope, team == Product.team, customer-iff-
# per-customer-prod, and the policyStatements IAM deny-set. Read strictly as YAML DATA (yq only). The Team list
# (envelope authority) comes from the TRUSTED base; the Product may be added by the same PR, so it is read from
# head as data.
#
# Env in:
#   BASE_DIR             trusted base checkout (Team envelopes)
#   HEAD_DIR             untrusted PR head checkout (the Environment + Product files)
#   ENVIRONMENT_FILES    space-separated added/modified gitops/environments/**/*.yaml (relative)
#   IAM_SENSITIVE        space-separated denied IAM service prefixes (default "iam sts organizations account")
# Requires: yq (mikefarah).
set -uo pipefail
: "${BASE_DIR:?}" "${HEAD_DIR:?}"
ENVIRONMENT_FILES="${ENVIRONMENT_FILES:-}"
IAM_SENSITIVE="${IAM_SENSITIVE:-iam sts organizations account}"

VALID_STAGES=" dev test uat staging prod "
VALID_TIERS=" standard elevated pci hipaa "
VALID_COMPUTE=" shared-namespace dedicated-namespace dedicated-nodes dedicated-cluster dedicated-account "

rc=0
note() { echo "::error::environment-gate: $1" >&2; rc=1; }
in_set() { case "$2" in *" $1 "*) return 0;; *) return 1;; esac; }

for rel in $ENVIRONMENT_FILES; do
  f="${HEAD_DIR}/${rel}"
  pf="$rel"
  [ -f "$f" ] || { note "${pf}: missing from head checkout"; continue; }
  [ -L "$f" ] && { note "${pf}: symlinks not allowed"; continue; }

  # identity + required
  [ "$(yq '.kind' "$f")" = "XEnvironment" ] || note "${pf}: kind must be XEnvironment"
  [ "$(yq '.apiVersion' "$f")" = "platform.refplat.org/v1beta1" ] || note "${pf}: apiVersion must be platform.refplat.org/v1beta1"
  team="$(yq '.spec.team // ""' "$f")"
  product="$(yq '.spec.product // ""' "$f")"
  stage="$(yq '.spec.stage // ""' "$f")"
  customer="$(yq '.spec.customer // ""' "$f")"
  [ -n "$team" ] || note "${pf}: spec.team is required"
  [ -n "$product" ] || note "${pf}: spec.product is required"
  [ -n "$stage" ] || note "${pf}: spec.stage is required"

  # path is load-bearing: gitops/environments/<team>/<product>/<stage>.yaml (the ApplicationSet git-files
  # generator derives ns/host from it). A path/content mismatch syncs to the wrong namespace.
  dir_product="$(basename "$(dirname "$rel")")"
  dir_team="$(basename "$(dirname "$(dirname "$rel")")")"
  [ "$dir_team" = "$team" ] || note "${pf}: directory team '${dir_team}' must equal spec.team '${team}'"
  [ "$dir_product" = "$product" ] || note "${pf}: directory product '${dir_product}' must equal spec.product '${product}'"

  # enums
  in_set "$stage" "$VALID_STAGES" || note "${pf}: spec.stage '${stage}' not in {dev,test,uat,staging,prod}"
  tier="$(yq '.spec.tier // "standard"' "$f")"
  in_set "$tier" "$VALID_TIERS" || note "${pf}: spec.tier '${tier}' not in {standard,elevated,pci,hipaa}"
  comp="$(yq '.spec.isolation.compute // ""' "$f")"
  [ -z "$comp" ] || in_set "$comp" "$VALID_COMPUTE" || note "${pf}: isolation.compute '${comp}' not in the ladder"

  # --- envelope shift-left: read the owning Team from the TRUSTED base ---
  team_f="${BASE_DIR}/gitops/teams/${team}.yaml"
  if [ -n "$team" ] && [ ! -f "$team_f" ]; then
    note "${pf}: spec.team '${team}' has no gitops/teams/${team}.yaml (envelope unknown)"
  elif [ -f "$team_f" ]; then
    # allowedStages is the v1beta1 field; allowedEnvironments/allowedStages were the v1alpha2/v1alpha3 names (same concept, renamed at
    # cutover). Read whichever is present so the gate is correct on both sides of the additive→v3 boundary.
    stages="$(yq '.spec.envelope.allowedStages[] // .spec.envelope.allowedEnvironments[]' "$team_f" 2>/dev/null | tr '\n' ' ')"
    [ -z "$stage" ] || [[ " $stages " == *" $stage "* ]] || note "${pf}: stage '${stage}' not in Team '${team}' allowedStages/allowedEnvironments ($stages)"
    tiers="$(yq '.spec.envelope.allowedTiers[]' "$team_f" 2>/dev/null | tr '\n' ' ')"
    [[ " $tiers " == *" $tier "* ]] || note "${pf}: tier '${tier}' not in Team '${team}' allowedTiers ($tiers)"
  fi

  # --- Product consistency (the Product may be added by this same PR → read from head as data) ---
  prod_f="${HEAD_DIR}/gitops/products/${team}/${product}.yaml"
  [ -f "$prod_f" ] || prod_f="${BASE_DIR}/gitops/products/${team}/${product}.yaml"
  if [ ! -f "$prod_f" ]; then
    note "${pf}: no Product gitops/products/${team}/${product}.yaml — an Environment must reference an existing Product"
  else
    pteam="$(yq '.spec.team // ""' "$prod_f")"
    [ "$pteam" = "$team" ] || note "${pf}: spec.team '${team}' does not match Product owner '${pteam}'"
    ptenancy="$(yq '.spec.tenancy // "pooled"' "$prod_f")"
    # customer-iff-per-customer-prod (mirrors #387)
    if [ "$ptenancy" = "per-customer" ] && in_set "$stage" " prod uat "; then
      [ -n "$customer" ] || note "${pf}: per-customer Product at stage '${stage}' requires spec.customer"
    elif [ -n "$customer" ]; then
      note "${pf}: spec.customer set but Product is '${ptenancy}' (or stage '${stage}' is not prod/uat)"
    fi
  fi

  # --- IAM deny-set on every Service's policyStatements (mirrors #387 policystatements-no-escalation) ---
  while IFS= read -r action; do
    [ -z "$action" ] && continue
    svc="$(printf '%s' "$action" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')"
    for s in $IAM_SENSITIVE; do
      [ "$svc" = "$s" ] && note "${pf}: a Service requests disallowed IAM action '${action}' (${IAM_SENSITIVE} + bare '*' are denied)"
    done
    [ "$svc" = "*" ] && note "${pf}: a Service requests a bare '*' IAM action (denied)"
  done < <(yq -r '.spec.services.*.permissions.aws.policyStatements[].actions[] // ""' "$f" 2>/dev/null)

  echo "   ${pf}: checked"
done

exit $rc
