#!/usr/bin/env bash
# Sync the operator's generated CRDs into the Terragrunt charts that install them (ADR-088/089).
#
# The operator's api/* Go types are the single schema SOURCE; controller-gen generates the CRDs; this
# vendors them into the charts that are the single LIVE INSTALL homes — because a Helm chart can't
# reference files outside its own directory. CI guards the copies instead: this script is both the updater
# (run it after changing the api types) and, via `git diff --exit-code`, the freshness check (see
# .github/workflows/operator.yml).
#
#   WorkforceRole, Person (api/v1beta1) -> the governance-registry chart (the hub registry, ADR-089)
#   Activation         (api/v1alpha1)   -> the activation-operator chart (the operator's own runtime CRD)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Regenerate the operator CRDs from the Go types (idempotent; builds controller-gen if missing).
make -C operators/activation manifests >/dev/null

SRC=operators/activation/config/crd/bases
GOVREG=infra/modules/crossplane/charts/governance-registry/templates
ADDON=infra/modules/activation-operator/chart/templates

sync() { # <generated-file> <dest-file>
  {
    printf '%s\n' \
      '# Canonical schema home (ADR-089 D4). Generated from operators/activation/api/* — the operator'\''s' \
      '# Go types. Regenerate with .github/scripts/sync-operator-crds.sh; CI checks freshness.'
    cat "$SRC/$1"
  } >"$2"
}

sync platform.refplat.org_workforceroles.yaml "$GOVREG/workforcerole-crd.yaml"
sync platform.refplat.org_people.yaml "$GOVREG/person-crd.yaml"
sync platform.refplat.org_activations.yaml "$ADDON/activation-crd.yaml"
