#!/usr/bin/env bash
# Agent gate (ADR-082 D6) — validate gitops/agents/**/*.yaml (XAgent claims) on a PR. The SHIFT-LEFT of the
# Kyverno restrict-agent-envelope / restrict-agent-control-plane admission policies: schema shape, placement
# hub-only, a pinned model id, the owning Product exists (team match), and the awsPermissions IAM deny-set —
# run pre-merge so a bad claim fails the PR instead of being rejected at admission. Read strictly as YAML DATA
# (yq only). The owning Product may be added by the same PR, so it is read from head as data (like environments).
#
# Env in:
#   BASE_DIR        trusted base checkout
#   HEAD_DIR        untrusted PR head checkout (the XAgent + Product files)
#   AGENT_FILES     space-separated added/modified gitops/agents/**/*.yaml (relative)
#   IAM_SENSITIVE   space-separated denied IAM service prefixes (default "iam sts organizations account")
# Requires: yq (mikefarah).
set -uo pipefail
: "${BASE_DIR:?}" "${HEAD_DIR:?}"
AGENT_FILES="${AGENT_FILES:-}"
IAM_SENSITIVE="${IAM_SENSITIVE:-iam sts organizations account}"

rc=0
note() { echo "::error::agent-gate: $1" >&2; rc=1; }

for rel in $AGENT_FILES; do
  case "$rel" in */README.md) continue;; esac
  f="${HEAD_DIR}/${rel}"
  pf="$rel"
  [ -f "$f" ] || { note "${pf}: missing from head checkout"; continue; }
  [ -L "$f" ] && { note "${pf}: symlinks not allowed"; continue; }

  # identity + required fields
  [ "$(yq '.kind' "$f")" = "XAgent" ] || { note "${pf}: kind must be XAgent"; continue; }
  team="$(yq -r '.spec.team // ""' "$f")"
  product="$(yq -r '.spec.product // ""' "$f")"
  [ -n "$team" ] || note "${pf}: spec.team is required"
  [ -n "$product" ] || note "${pf}: spec.product is required"

  # placement hub-only (absent → default platform, OK)
  cluster="$(yq -r '.spec.placement.cluster // "platform"' "$f")"
  [ "$cluster" = "platform" ] || note "${pf}: spec.placement.cluster must be 'platform' (ADR-082 D2), got '${cluster}'"

  # a bedrock agent must pin a model id (no floating model — ADR-074 lifecycle)
  provider="$(yq -r '.spec.model.provider // "bedrock"' "$f")"
  if [ "$provider" = "bedrock" ]; then
    [ -n "$(yq -r '.spec.model.id // ""' "$f")" ] || note "${pf}: spec.model.id is required (a pinned Bedrock model/inference-profile id)"
  fi

  # the owning Product must exist (head, as data) and its team must match
  if [ -n "$team" ] && [ -n "$product" ]; then
    prod="${HEAD_DIR}/gitops/products/${team}/${product}.yaml"
    if [ ! -f "$prod" ]; then
      note "${pf}: owning Product gitops/products/${team}/${product}.yaml not found"
    else
      pteam="$(yq -r '.spec.team // ""' "$prod")"
      [ "$pteam" = "$team" ] || note "${pf}: spec.team '${team}' != owning Product.spec.team '${pteam}'"
    fi
  fi

  # awsPermissions IAM deny-set (the same escalation guard as the tenant envelope, ADR-062 §4)
  while IFS= read -r action; do
    [ -n "$action" ] || continue
    svc="$(printf '%s' "$action" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')"
    for deny in $IAM_SENSITIVE; do
      if [ "$svc" = "$deny" ] || [ "$svc" = "*" ]; then
        note "${pf}: awsPermissions action '${action}' is denied (the services ${IAM_SENSITIVE} and bare '*' are not allowed)"
        break
      fi
    done
  done < <(yq -r '(.spec.awsPermissions.policyStatements // [])[].actions[]' "$f")
done

exit $rc
