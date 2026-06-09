#!/usr/bin/env bash
# Shift-left Kyverno validation: render the platform tenant policies for a team and apply them to an
# app's rendered manifests, failing if any policy is violated. Mirrors what admission enforces, so an
# app PR fails BEFORE merge instead of being rejected at deploy. Cluster-free; no AWS/secrets needed.
#
# Inputs (env):
#   TEAM            tenant key (e.g. alpha) — namespace is team-<TEAM>
#   MANIFESTS_PATH  path to the app's kustomize dir (kustomization.yaml)
#   POLICIES_CHART  path to infra/modules/policy/policies-chart
#   ECR_REGISTRY      platform ECR host (e.g. 829808296602.dkr.ecr.us-east-1.amazonaws.com)
#   HOSTNAMES_JSON    JSON array of the team's allowed route hostnames (default [])
#   INJECT_HOSTS_JSON JSON array of route hostnames to inject into the app's routes (mirrors argocd-apps).
#                     Empty/unset → no injection (validate the manifest's own hostnames).
#   TENANT_LABEL      tenant namespace label key (default platform.refplat.org/tenant)
#
# Requires: helm, kubectl (for `kubectl kustomize`), kyverno CLI (pin to the chart appVersion), yq (inject).
set -euo pipefail

TEAM="${TEAM:?set TEAM}"
MANIFESTS_PATH="${MANIFESTS_PATH:?set MANIFESTS_PATH}"
POLICIES_CHART="${POLICIES_CHART:?set POLICIES_CHART}"
ECR_REGISTRY="${ECR_REGISTRY:?set ECR_REGISTRY}"
HOSTNAMES_JSON="${HOSTNAMES_JSON:-[]}"
INJECT_HOSTS_JSON="${INJECT_HOSTS_JSON:-}"
TENANT_LABEL="${TENANT_LABEL:-platform.refplat.org/tenant}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▸ Rendering platform policies for team-${TEAM} ..."
# mutate applied (so validation matches the cluster's auto-injected defaults); verifyImages OFF (the
# image isn't built/signed at PR time); cleanup OFF (runtime GC, not an admission check).
helm template kpp "$POLICIES_CHART" \
  --set validationFailureAction=Enforce \
  --set failurePolicy=Fail \
  --set complianceTier=standard \
  --set enableMutateDefaults=true \
  --set enableImageVerification=false \
  --set enableCleanup=false \
  --set-json "allowedRegistries=[\"${ECR_REGISTRY}\"]" \
  --set-json "tenantRegistryMap={\"${TEAM}\":\"${ECR_REGISTRY}/team-${TEAM}\"}" \
  --set-json "tenantHostnamePatterns={\"${TEAM}\":${HOSTNAMES_JSON}}" \
  >"$WORK/policies.yaml"

echo "▸ Rendering app manifests from ${MANIFESTS_PATH} ..."
kubectl kustomize "$MANIFESTS_PATH" >"$WORK/resources.yaml"

# Inject the derived route hostnames the way argocd-apps does at deploy (ADR-060/061), so the app repo can
# ship a placeholder host and the shift-left validates the SAME hostnames admission will see. Replaces the
# whole spec.hostnames on every Gateway-API route; leaves non-route resources (and other violations) intact.
if [ -n "$INJECT_HOSTS_JSON" ] && [ "$INJECT_HOSTS_JSON" != "[]" ]; then
  echo "▸ Injecting route hostnames ${INJECT_HOSTS_JSON} ..."
  INJECT_HOSTS_JSON="$INJECT_HOSTS_JSON" yq -i \
    '(select(.kind == "HTTPRoute" or .kind == "GRPCRoute" or .kind == "TLSRoute") | .spec.hostnames) = env(INJECT_HOSTS_JSON)' \
    "$WORK/resources.yaml"
fi

# Without a live cluster the CLI needs to be told the team namespace carries the tenant label, so the
# tenant-scoped policies (which match on it) apply.
cat >"$WORK/values.yaml" <<EOF
apiVersion: cli.kyverno.io/v1alpha1
kind: Values
metadata:
  name: namespace-labels
namespaceSelector:
  - name: team-${TEAM}
    labels:
      ${TENANT_LABEL}: ${TEAM}
EOF

echo "▸ Applying policies (kyverno apply) ..."
# kyverno apply exits non-zero whenever a resource fails a validate policy, so we tolerate that and key
# off the parsed summary instead — distinguishing genuine policy fails from CLI errors.
OUT="$(kyverno apply "$WORK/policies.yaml" --resource "$WORK/resources.yaml" --values-file "$WORK/values.yaml" 2>&1 || true)"
printf '%s\n' "$OUT"

SUMMARY="$(printf '%s\n' "$OUT" | grep -oE 'pass: [0-9]+, fail: [0-9]+, warn: [0-9]+, error: [0-9]+, skip: [0-9]+' | tail -1)"
if [ -z "$SUMMARY" ]; then
  echo "::error::kyverno apply produced no summary — treating as failure."
  exit 1
fi
FAIL="$(printf '%s' "$SUMMARY" | sed -E 's/.*fail: ([0-9]+).*/\1/')"
ERROR="$(printf '%s' "$SUMMARY" | sed -E 's/.*error: ([0-9]+).*/\1/')"

echo "──────────────────────────────────────────"
echo "Result for team-${TEAM}: ${SUMMARY}"
if [ "${FAIL:-1}" -gt 0 ] || [ "${ERROR:-1}" -gt 0 ]; then
  echo "::error::Policy validation FAILED (fail=${FAIL}, error=${ERROR}). The manifests above would be rejected at admission — fix them before merge."
  exit 1
fi
echo "✅ Policy validation passed for team-${TEAM}."
