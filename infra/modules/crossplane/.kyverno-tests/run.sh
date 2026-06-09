#!/usr/bin/env bash
# Renders the crossplane tenant-policies chart and tests the two tenant control-plane Kyverno ClusterPolicies
# (restrict-tenant-envelope + restrict-tenant-control-plane). These moved out of the policy module's
# policies-chart so they install AFTER the Crossplane CRDs exist (see charts/tenant-policies/Chart.yaml); the
# tests moved with them. Cluster-free: matches CI. Requires `helm` and `kyverno` (pin the CLI to the chart's
# appVersion). Run by the kyverno-policy-test CI job, which already has both tools.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$DIR/../charts/tenant-policies"
mkdir -p "$DIR/rendered"

# ---------------------------------------------------------------------------
# restrict-tenant-control-plane — render-validity (the deny rule reads request.userInfo, which kyverno apply
# can't mock offline, so we assert the template renders the policy gating the right kinds + skip list).
# ---------------------------------------------------------------------------
echo "Rendering tenant-control-plane policy (template validity) ..."
CPPOL="$DIR/rendered/tenant-control-plane.yaml"
helm template ktp "$CHART" --show-only templates/tenant-control-plane.yaml >"$CPPOL"
grep -q 'name: restrict-tenant-control-plane' "$CPPOL" || { echo "FAIL: control-plane policy did not render"; exit 1; }
grep -q 'platform.refplat.org/v1alpha1/XTenant' "$CPPOL" || { echo "FAIL: control-plane must match XTenant"; exit 1; }
grep -q 'aws.upbound.io/v1beta1/ProviderConfig' "$CPPOL" || { echo "FAIL: control-plane must match the AWS ProviderConfig"; exit 1; }
grep -q 'system:serviceaccount:crossplane-system:\*' "$CPPOL" || { echo "FAIL: control-plane must skip crossplane-system principals"; exit 1; }
echo "tenant-control-plane render-check passed."

# ---------------------------------------------------------------------------
# restrict-tenant-envelope (ADR-049 A2b). It reads the projected Team CR via an apiCall, which `kyverno test`
# can't unit-test offline (the per-resource values mock is removed in 1.18 and globalValues is uniform per run).
# So we drive `kyverno apply` once per Team envelope — mocking the Team via globalValues — and assert the
# per-rule outcomes. Behavioral, cluster-free. (Identical to the suite that lived in the policy module.)
# ---------------------------------------------------------------------------
echo "Testing tenant-envelope policy (envelope plane) ..."
ENVPOL="$DIR/rendered/tenant-envelope.yaml"
helm template ktp "$CHART" --show-only templates/tenant-envelope.yaml >"$ENVPOL"
ED="$DIR/tenant-envelope"
run_env() { kyverno apply "$ENVPOL" --resource "$ED/$1" --values-file "$ED/$2" 2>&1 || true; }
must_flag() { # output resource rule
  grep -q "XTenant/$2 failed" <<<"$1" || { echo "FAIL: envelope: $2 should be flagged"; printf '%s\n' "$1"; exit 1; }
  grep -q "$3"                 <<<"$1" || { echo "FAIL: envelope: $2 expected rule '$3'"; printf '%s\n' "$1"; exit 1; }
}
must_admit() { # output resource
  if grep -q "XTenant/$2 failed" <<<"$1"; then echo "FAIL: envelope: $2 should pass"; printf '%s\n' "$1"; exit 1; fi
}

OUT="$(run_env resources-payments.yaml values-payments.yaml)"
must_admit "$OUT" ok
must_admit "$OUT" wildok
must_flag  "$OUT" badtier   "tier-within-envelope"
must_flag  "$OUT" badloc    "residency-within-envelope"
must_flag  "$OUT" overquota "quota-within-cap"

OUT="$(run_env resources-alpha.yaml values-alpha.yaml)"
must_admit "$OUT" okalpha
must_flag  "$OUT" badenv "environment-within-envelope"

OUT="$(run_env resources-ghost.yaml values-ghost.yaml)"
must_flag  "$OUT" ghostteam "team-must-exist"

echo "tenant-envelope policy checks passed (tier/env/residency/quota/team-existence)."
