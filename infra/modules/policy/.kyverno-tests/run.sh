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
MUT="$(kyverno apply rendered/policies.yaml --resource resources/mutate-input.yaml --values-file values.yaml -o "$DIR/rendered/mutated" 2>&1 || true)"
APPLIED="$(printf '%s' "$MUT" | grep -c 'Mutation has been applied successfully' || true)"
if ! grep -q 'error: 0' <<<"$MUT"; then
  echo "FAIL: mutate produced errors"; printf '%s\n' "$MUT"; exit 1
fi
if [ "$APPLIED" -lt 2 ]; then
  echo "FAIL: expected >=2 mutations on the bare Deployment, got $APPLIED"; printf '%s\n' "$MUT"; exit 1
fi
echo "Mutation smoke-check passed ($APPLIED mutations applied via autogen, 0 errors)."

# Field-level assertions on the mutated Deployment: mutate-pod-defaults must inject the ADR-085 graceful-drain
# defaults under autogen (spec.template.spec) — the mutation count above can't distinguish which fields landed,
# so grep the actual patched resource. topologySpreadConstraints is NOT asserted (it lives in the scaffolder,
# not this mutate — ADR-085 D2).
MUTATED="$(cat "$DIR/rendered/mutated"/* 2>/dev/null)"
for field in 'terminationGracePeriodSeconds: 30' 'preStop:' 'seconds: 10'; do
  grep -q "$field" <<<"$MUTATED" || { echo "FAIL: mutate did not inject '$field' on the bare Deployment"; printf '%s\n' "$MUTATED"; exit 1; }
done
echo "Graceful-drain field-injection check passed (terminationGracePeriodSeconds + preStop sleep)."

# Render-check the per-PRODUCT supply-chain verification (verify-images-product + verify-attestations-product,
# ADR-067/069 §6 — the successors to the per-team verify-images/verify-attestations, which moved here from
# the retired per-team policies at the cutover). Every product uses the SHARED trusted-ci signer (build-sign for
# the signature + SBOM, slsa-provenance for provenance), gated to the product by the cert's
# githubWorkflowRepository extension (= the Product repo). verifyImages can't be unit-tested offline (cosign/Rekor
# needs a live cluster — the Audit PolicyReport is the real gate); here we assert the templates render the right
# identity per product, plus the optional bespoke app-signed identities.
echo "Rendering per-product verify-images/attestations (template validity) ..."
VP="$(helm template kpp "$CHART" \
  --set enableImageVerification=true \
  --set enableAttestationVerification=true \
  --set-json 'verifySubjectsProduct={"alpha-demo":{"team":"alpha","product":"demo","repo":"asanexample/alpha-demo","registryPrefix":"829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha/demo"}}')"
grep -q 'name: verify-images-product-alpha-demo' <<<"$VP" || { echo "FAIL: verify-images-product-alpha-demo did not render"; exit 1; }
grep -q 'name: verify-attestations-product-alpha-demo' <<<"$VP" || { echo "FAIL: verify-attestations-product-alpha-demo did not render"; exit 1; }
grep -q 'asanexample/trusted-ci' <<<"$VP" || { echo "FAIL: per-product verification must use the trusted-ci subject"; exit 1; }
grep -q 'githubWorkflowRepository: "asanexample/alpha-demo"' <<<"$VP" || { echo "FAIL: per-product caller extension (= the Product repo) missing"; exit 1; }
grep -q 'team-alpha/demo-\*' <<<"$VP" || { echo "FAIL: per-product image scope team-alpha/demo-* missing"; exit 1; }
echo "per-product verify-images/attestations render-check passed."

# NOTE: the restrict-environment-envelope / restrict-environment-control-plane policies (and their tests) moved to the
# crossplane module — infra/modules/crossplane/.kyverno-tests/run.sh — because they match Crossplane CRDs and
# must install after them (see infra/modules/crossplane/charts/environment-policies/Chart.yaml).
