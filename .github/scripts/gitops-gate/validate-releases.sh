#!/usr/bin/env bash
# Release gate (ADR-071) — validate gitops/releases/**/*.yaml (the control-plane deployed-digest records) on a
# PR. A Release is CI-authored (the promote workflow opens a gated PR bumping one digest); the per-Product
# ApplicationSet reads it and injects the digest, so the app repo's main is never written. This gate proves a
# release bump is well-formed and joins to a real Environment+Service before it can auto-merge:
#   - schema shape: kind/apiVersion, ≥1 service, every digest is a real `sha256:<64hex>` MANIFEST digest
#     (a mutable tag must never reach a cluster);
#   - the path is load-bearing — gitops/releases/<team>/<product>/<file> must have a SIBLING Environment claim
#     gitops/environments/<team>/<product>/<file>, and spec.environmentRef must equal that claim's name (else the
#     ApplicationSet would inject a digest into the wrong / a non-existent Environment);
#   - every released Service is DECLARED on that Environment (spec.services.<svc>) — you can only deploy a Service
#     the Environment actually realizes.
# Read strictly as YAML DATA (yq only). The Environment claim (the join authority) may be added by the same PR,
# so it is read from head, falling back to the trusted base.
#
# Env in:
#   BASE_DIR        trusted base checkout
#   HEAD_DIR        untrusted PR head checkout (the Release + maybe its Environment claim)
#   RELEASE_FILES   space-separated added/modified gitops/releases/**/*.yaml (relative)
# Requires: yq (mikefarah).
set -uo pipefail
: "${BASE_DIR:?}" "${HEAD_DIR:?}"
RELEASE_FILES="${RELEASE_FILES:-}"

DIGEST_RE='^sha256:[a-f0-9]{64}$'

rc=0
note() { echo "::error::release-gate: $1" >&2; rc=1; }

for rel in $RELEASE_FILES; do
  f="${HEAD_DIR}/${rel}"
  pf="$rel"
  [ -f "$f" ] || { note "${pf}: missing from head checkout"; continue; }
  [ -L "$f" ] && { note "${pf}: symlinks not allowed"; continue; }

  # identity (yq -r so the compare is robust to scalar-quoting yq builds, matching validate-environments.sh)
  [ "$(yq -r '.kind' "$f")" = "Release" ] || note "${pf}: kind must be Release"
  [ "$(yq -r '.apiVersion' "$f")" = "platform.refplat.org/v1beta1" ] || note "${pf}: apiVersion must be platform.refplat.org/v1beta1"

  envref="$(yq -r '.spec.environmentRef // ""' "$f")"
  [ -n "$envref" ] || note "${pf}: spec.environmentRef is required"

  # path is load-bearing: gitops/releases/<team>/<product>/<file> joins to its SIBLING target — either a tenant/
  # platform Environment claim at gitops/environments/<team>/<product>/<file>, OR (for platform agents — ADR-082,
  # XAgent not XEnvironment) the agent claim at gitops/agents/<product>.yaml. The path's <product> ties the
  # release to its target either way. Derive team/product/file from the path.
  dir_product="$(basename "$(dirname "$rel")")"
  dir_team="$(basename "$(dirname "$(dirname "$rel")")")"
  fname="$(basename "$rel")"
  env_rel="gitops/environments/${dir_team}/${dir_product}/${fname}"
  env_f="${HEAD_DIR}/${env_rel}"
  [ -f "$env_f" ] || env_f="${BASE_DIR}/${env_rel}"
  agent_rel="gitops/agents/${dir_product}.yaml"
  agent_f="${HEAD_DIR}/${agent_rel}"
  [ -f "$agent_f" ] || agent_f="${BASE_DIR}/${agent_rel}"
  if [ -f "$env_f" ]; then
    env_name="$(yq -r '.metadata.name // ""' "$env_f")"
    [ "$envref" = "$env_name" ] || note "${pf}: spec.environmentRef '${envref}' must equal the Environment claim's metadata.name '${env_name}' (${env_rel})"
  elif [ ! -f "$agent_f" ]; then
    note "${pf}: no sibling Environment claim ${env_rel} nor Agent claim ${agent_rel} — a Release must target an existing Environment or Agent"
  fi

  # ≥1 service; each released Service must be DECLARED on the Environment; each digest is a real manifest digest.
  svcs="$(yq -r '.spec.services | keys | .[]' "$f" 2>/dev/null)"
  [ -n "$svcs" ] || note "${pf}: spec.services must declare at least one Service"
  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    digest="$(yq -r ".spec.services.\"${svc}\".digest // \"\"" "$f")"
    [[ "$digest" =~ $DIGEST_RE ]] || note "${pf}: service '${svc}' digest '${digest}' is not a sha256:<64 hex> manifest digest"
    if [ -f "$env_f" ]; then
      declared="$(yq -r ".spec.services | has(\"${svc}\")" "$env_f" 2>/dev/null)"
      [ "$declared" = "true" ] || note "${pf}: service '${svc}' is not declared on Environment '${envref}' (spec.services) — you can only release a Service the Environment realizes"
    fi
  done <<<"$svcs"

  echo "   ${pf}: checked"
done

exit $rc
