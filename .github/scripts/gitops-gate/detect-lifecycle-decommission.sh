#!/usr/bin/env bash
# gitops gate — lifecycle-decommission detector (Deprovision Product, ADR-062). Emits `decommission=true`
# when the PR transitions ANY Environment claim INTO a suspend state (spec.lifecycle.phase ∈
# decommissioning|suspended) in HEAD. Used to EXCLUDE such PRs from auto-merge: decommissioning a Product
# (or a single Environment) zeroes the ResourceQuota and drains workloads — INCLUDING prod — so even though
# it's reversible and non-deletion, it must be reviewer-merged, not self-service auto-merged. A `reactivate`
# (phase → active) is restorative and follows the normal auto-merge path.
#
# Env in:  HEAD_DIR (the untrusted PR registry checkout), ENVIRONMENT_FILES (space-separated, relative).
# Out:     $GITHUB_OUTPUT (or stdout) — decommission=true|false. Requires yq.
set -uo pipefail

decommission=false
for f in ${ENVIRONMENT_FILES:-}; do
  hf="${HEAD_DIR:-head}/${f}"
  [ -f "$hf" ] || continue
  case "$(yq -r '.spec.lifecycle.phase // "active"' "$hf" 2>/dev/null)" in
    decommissioning | suspended) decommission=true; break ;;
  esac
done

echo "decommission=${decommission}" >>"${GITHUB_OUTPUT:-/dev/stdout}"
