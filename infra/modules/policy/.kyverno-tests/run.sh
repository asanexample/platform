#!/usr/bin/env bash
# Renders the platform policies chart and runs the Kyverno CLI test suite against it.
# Cluster-free: matches CI. Requires `helm` and `kyverno` (pin the CLI to the chart's appVersion).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$DIR/../policies-chart"

mkdir -p "$DIR/rendered"
helm template kpp "$CHART" \
  --set validationFailureAction=Enforce \
  --set failurePolicy=Fail \
  --set complianceTier=standard \
  --set-json 'allowedRegistries=["829808296602.dkr.ecr.us-east-1.amazonaws.com"]' \
  --set-json 'tenantRegistryMap={"alpha":"829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha"}' \
  --set-json 'tenantHostnamePatterns={"alpha":["demo.preprod.aws.refplat.org"]}' \
  >"$DIR/rendered/policies.yaml"

cd "$DIR"
kyverno test .

# Mutation smoke-check: the three mutate policies must inject their defaults on a bare pod with no
# errors. (kyverno test's declarative patchedResources comparison is brittle across CLI versions, so
# we assert success + a clean error count here instead.)
echo "Running mutation smoke-check ..."
# kyverno apply exits non-zero when a resource fails a validate policy (the bare pod intentionally
# does), so tolerate that and inspect the captured output instead.
MUT="$(kyverno apply rendered/policies.yaml --resource resources/mutate-input.yaml --values-file values.yaml 2>&1 || true)"
APPLIED="$(printf '%s' "$MUT" | grep -c 'Mutation has been applied successfully' || true)"
if ! printf '%s' "$MUT" | grep -q 'error: 0'; then
  echo "FAIL: mutate produced errors"; printf '%s\n' "$MUT"; exit 1
fi
if [ "$APPLIED" -lt 2 ]; then
  echo "FAIL: expected >=2 mutations on the bare Deployment, got $APPLIED"; printf '%s\n' "$MUT"; exit 1
fi
echo "Mutation smoke-check passed ($APPLIED mutations applied via autogen, 0 errors)."

# Render-check the SLSA Build L3 isolated-provenance Audit policy (#131 P2). verifyImages policies can't
# be unit-tested offline — cosign/Rekor verification needs a live cluster, so the Audit PolicyReport is
# the real gate. Here we only assert the template renders valid YAML with the per-team caller extension.
echo "Rendering SLSA-L3 isolated-provenance policy (template validity) ..."
L3="$(helm template kpp "$CHART" \
  --set enableImageVerification=true \
  --set enableAttestationVerification=true \
  --set enableL3ProvenanceAudit=true \
  --set-json 'tenantRegistryMap={"alpha":"829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha"}' \
  --set-json 'attestCallerRepos={"alpha":"asanexample/app-alpha"}' \
  --show-only templates/verify-attestations-l3.yaml)"
printf '%s' "$L3" | grep -q 'name: verify-attestations-l3-team-alpha' || { echo "FAIL: L3 policy did not render"; exit 1; }
printf '%s' "$L3" | grep -q 'githubWorkflowRepository: "asanexample/app-alpha"' || { echo "FAIL: per-team caller extension missing"; exit 1; }
printf '%s' "$L3" | grep -q 'validationFailureAction: Audit' || { echo "FAIL: L3 policy must be Audit"; exit 1; }
echo "SLSA-L3 policy render-check passed."
