#!/usr/bin/env bash
# Environment gate (#388) — composition render. Proves each PR XEnvironment claim actually BUILDS against the
# Composition (the Environment+Product join, the go-templating function pipeline) — catching a claim that is
# schema/envelope-valid but render-breaking (a bad service config, an un-templatable value). Mirrors the Tenant
# Claims Gate's render step (validate-claims.sh) for the surface.
#
# The Composition, functions, and EnvironmentConfig all come from the TRUSTED base; only the claim is from head,
# and `crossplane render` reads it as data (no cluster, Docker-run functions).
#
# Env in:
#   BASE_DIR             trusted base checkout (Composition + render fixtures)
#   HEAD_DIR             untrusted PR head checkout (the Environment claims)
#   ENVIRONMENT_FILES    space-separated gitops/environments/**/*.yaml (relative)
# Requires: crossplane (crank), docker.
set -uo pipefail
: "${BASE_DIR:?}" "${HEAD_DIR:?}"
ENVIRONMENT_FILES="${ENVIRONMENT_FILES:-}"

COMPOSITION="${BASE_DIR}/infra/modules/crossplane/charts/environment-api/files/composition.yaml"
FIXTURES="${BASE_DIR}/infra/modules/crossplane/.environment-api-tests/render"
FNS="${FIXTURES}/functions.yaml"
ENVCFG="${FIXTURES}/environmentconfig.yaml"

command -v crossplane >/dev/null 2>&1 || { echo "::error::render-environments: crossplane CLI not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "::error::render-environments: docker is required for crossplane render"; exit 1; }
for p in "$COMPOSITION" "$FNS" "$ENVCFG"; do
  [ -f "$p" ] || { echo "::error::render-environments: missing trusted input $p"; exit 1; }
done

rc=0
for rel in $ENVIRONMENT_FILES; do
  f="${HEAD_DIR}/${rel}"
  [ -f "$f" ] || { echo "::error::render-environments: ${rel}: missing from head checkout"; rc=1; continue; }
  if ! out="$(crossplane render "$f" "$COMPOSITION" "$FNS" --extra-resources "$ENVCFG" 2>&1)"; then
    printf '%s\n' "$out" >&2
    echo "::error::render-environments: ${rel}: composition render failed"; rc=1; continue
  fi
  grep -q 'kind:' <<<"$out" || { echo "::error::render-environments: ${rel}: composition render produced no output"; rc=1; continue; }
  echo "   ${rel}: rendered"
done

exit $rc
