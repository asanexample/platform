#!/usr/bin/env bash
# Sync the governance-registry chart's CRD copies from the operator's generated CRDs (ADR-089 D4).
#
# The operator's api/v1beta1 Go types are the single schema SOURCE; controller-gen generates the CRDs;
# this vendors them into the governance-registry chart, which is the single LIVE INSTALL home. The copy
# exists because a Helm chart can't reference files outside its own directory — so CI guards it instead:
# this script is both the updater (run it after changing the v1beta1 types) and, via `git diff
# --exit-code`, the freshness check (see .github/workflows/operator.yml).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Regenerate the operator CRDs from the Go types (idempotent; builds controller-gen if missing).
make -C operators/activation manifests >/dev/null

SRC=operators/activation/config/crd/bases
DST=infra/modules/crossplane/charts/governance-registry/templates

sync() { # <generated-file> <chart-file>
  {
    printf '%s\n' \
      '# Canonical schema home (ADR-089 D4). Generated from operators/activation/api/v1beta1 — the operator'\''s' \
      '# Go read-shim types. Regenerate with .github/scripts/sync-governance-registry-crds.sh; CI checks freshness.'
    cat "$SRC/$1"
  } >"$DST/$2"
}

sync platform.refplat.org_workforceroles.yaml workforcerole-crd.yaml
sync platform.refplat.org_people.yaml person-crd.yaml
