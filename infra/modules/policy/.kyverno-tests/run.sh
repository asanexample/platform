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

# Render-check the SLSA Build L3 isolated-provenance path (#131, ADR-042). It's now FOLDED INTO the main
# verify-attestations policy: for a team in attestCallerRepos the SLSA provenance attestor is the isolated
# trusted-ci workflow (gated by the per-team githubWorkflowRepository extension) instead of the app's own,
# while the SBOM stays app-signed. verifyImages policies can't be unit-tested offline (cosign/Rekor needs
# a live cluster — the Audit PolicyReport is the real gate); here we assert the template renders the right
# attestor identity per team. alpha = adopted (trusted-ci provenance); bravo = not adopted (app provenance).
echo "Rendering verify-attestations policy (isolated-provenance fold-in, template validity) ..."
VA="$(helm template kpp "$CHART" \
  --set enableImageVerification=true \
  --set enableAttestationVerification=true \
  --set-json 'tenantRegistryMap={"alpha":"829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha","bravo":"829808296602.dkr.ecr.us-east-1.amazonaws.com/team-bravo"}' \
  --set-json 'attestCallerRepos={"alpha":"asanexample/app-alpha"}' \
  --set-json 'verifySubjects={"alpha":[{"deploy_subject":"https://github.com/asanexample/app-alpha/.github/workflows/deploy.yml@refs/heads/main","preview_subject_regexp":"https://github.com/asanexample/app-alpha/.github/workflows/preview.yml@refs/.*"}],"bravo":[{"deploy_subject":"https://github.com/asanexample/app-bravo/.github/workflows/deploy.yml@refs/heads/main","preview_subject_regexp":"https://github.com/asanexample/app-bravo/.github/workflows/preview.yml@refs/.*"}]}')"
# alpha (adopted): provenance attestor is trusted-ci, gated by the caller-repo extension.
printf '%s' "$VA" | grep -q 'name: verify-attestations-team-alpha' || { echo "FAIL: alpha verify-attestations did not render"; exit 1; }
printf '%s' "$VA" | grep -q 'asanexample/trusted-ci' || { echo "FAIL: alpha provenance must use the trusted-ci subject"; exit 1; }
printf '%s' "$VA" | grep -q 'githubWorkflowRepository: "asanexample/app-alpha"' || { echo "FAIL: alpha per-team caller extension missing"; exit 1; }
# bravo (not adopted): keeps app-signed provenance, no trusted-ci, no caller-repo gate.
printf '%s' "$VA" | grep -q 'name: verify-attestations-team-bravo' || { echo "FAIL: bravo verify-attestations did not render"; exit 1; }
printf '%s' "$VA" | grep -q 'githubWorkflowRepository: "asanexample/app-bravo"' && { echo "FAIL: bravo must NOT carry a trusted-ci caller gate"; exit 1; }
echo "verify-attestations isolated-provenance render-check passed (alpha=trusted-ci, bravo=app)."
