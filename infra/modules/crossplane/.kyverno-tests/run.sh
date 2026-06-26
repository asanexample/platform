#!/usr/bin/env bash
# Renders the crossplane environment-policies chart and tests its two control-plane Kyverno ClusterPolicies
# (restrict-environment-envelope + restrict-environment-control-plane). These moved out of the policy module's
# policies-chart so they install AFTER the Crossplane CRDs exist (see charts/environment-policies/Chart.yaml); the
# tests moved with them. Cluster-free: matches CI. Requires `helm` and `kyverno` (pin the CLI to the chart's
# appVersion). Run by the kyverno-policy-test CI job, which already has both tools.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$DIR/../charts/environment-policies"
mkdir -p "$DIR/rendered"

# ---------------------------------------------------------------------------
# restrict-environment-control-plane — render-validity (the deny rule reads request.userInfo, which kyverno apply
# can't mock offline, so we assert the template renders the policy gating the right kinds + skip list).
# ---------------------------------------------------------------------------
echo "Rendering environment-control-plane policy (template validity) ..."
CPPOL="$DIR/rendered/environment-control-plane.yaml"
helm template ktp "$CHART" --show-only templates/environment-control-plane.yaml >"$CPPOL"
grep -q 'name: restrict-environment-control-plane' "$CPPOL" || { echo "FAIL: control-plane policy did not render"; exit 1; }
grep -q 'platform.refplat.org/v1beta1/XEnvironment' "$CPPOL" || { echo "FAIL: control-plane must match XEnvironment"; exit 1; }
grep -q 'aws.upbound.io/v1beta1/ProviderConfig' "$CPPOL" || { echo "FAIL: control-plane must match the AWS ProviderConfig"; exit 1; }
grep -q 'system:serviceaccount:crossplane-system:\*' "$CPPOL" || { echo "FAIL: control-plane must skip crossplane-system principals"; exit 1; }
echo "environment-control-plane render-check passed."

# ---------------------------------------------------------------------------
# restrict-environment-envelope (ADR-067 #387). It reads the projected Team + Product CRs via apiCalls, which
# `kyverno test` can't unit-test offline (the per-resource values mock is removed in 1.18 and globalValues is
# uniform per run). So we drive `kyverno apply` once per (Team, Product) mock — both via globalValues — and
# assert the per-rule outcomes. Behavioral, cluster-free. The sibling v2 restrict-environment-envelope test retired
# with the XTenant API.
# ---------------------------------------------------------------------------
echo "Testing environment-envelope policy (envelope plane) ..."
ENVPOL="$DIR/rendered/environment-envelope.yaml"
# envelopeSkipReconcilePrincipal="" omits spec.webhookConfiguration.matchConditions (TD2-04): that field is
# admission-webhook ROUTING (skip Crossplane's reconcile UPDATEs), not rule deny-logic, so it's irrelevant to
# this behavioral test — and `kyverno apply` v1.18.1 panics (nil-pointer) on matchConditions offline. The live
# Kyverno CRD supports the field; it's exercised in-cluster, not here.
helm template ktp "$CHART" --set enableEnvironmentEnvelope=true --set envelopeSkipReconcilePrincipal= --show-only templates/environment-envelope.yaml >"$ENVPOL"
ED="$DIR/environment-envelope"
run_env() { kyverno apply "$ENVPOL" --resource "$ED/$1" --values-file "$ED/$2" 2>&1 || true; }
must_flag() { # output resource rule
  grep -q "XEnvironment/$2 failed" <<<"$1" || { echo "FAIL: envelope: $2 should be flagged"; printf '%s\n' "$1"; exit 1; }
  grep -q "$3"                     <<<"$1" || { echo "FAIL: envelope: $2 expected rule '$3'"; printf '%s\n' "$1"; exit 1; }
}
must_admit() { # output resource
  if grep -q "XEnvironment/$2 failed" <<<"$1"; then echo "FAIL: envelope: $2 should pass"; printf '%s\n' "$1"; exit 1; fi
}

# Team alpha (tiers [standard], stages [dev,prod], loc [*], quota cap) + pooled Product alpha-demo.
OUT="$(run_env resources-alpha.yaml values-alpha.yaml)"
must_admit "$OUT" okenv
must_flag  "$OUT" badtier    "tier-within-envelope"
must_flag  "$OUT" badstage   "stage-within-envelope"
must_flag  "$OUT" overquota  "quota-within-cap"
must_flag  "$OUT" pooledcust "customer-forbidden-on-pooled"
must_flag  "$OUT" trustcreep "platformtrust-clusterroles-within-envelope" # tenant can't self-grant cluster RBAC (ADR-081)

# No projected Team → team-must-exist.
OUT="$(run_env resources-ghost.yaml values-ghost.yaml)"
must_flag  "$OUT" ghostenv "team-must-exist"

# Product alpha-demo resolves but is owned by bravo → team-matches-product.
OUT="$(run_env resources-mismatch.yaml values-mismatch.yaml)"
must_flag  "$OUT" mismatchenv "team-matches-product"

# Team restricted to aws:us-east-1 → the residency precondition fires (it skips for '*' envelopes).
OUT="$(run_env resources-residency.yaml values-residency.yaml)"
must_admit "$OUT" okres
must_flag  "$OUT" badloc "residency-within-envelope"

# per-customer Product alpha-shop: customer REQUIRED at prod.
OUT="$(run_env resources-customer.yaml values-customer.yaml)"
must_admit "$OUT" okcust
must_flag  "$OUT" nocust "customer-required-per-customer-prod"

# policystatements-no-escalation (ADR-062 §4, #282) — platform-global IAM deny-set over spec.services. All
# within the alpha envelope so only the IAM rule can flag.
OUT="$(run_env resources-iam.yaml values-iam.yaml)"
must_admit "$OUT" iamok      # compliant s3 statement
must_admit "$OUT" iamnoperm  # no permissions block (foreach no-op)
must_flag  "$OUT" iambad   "policystatements-no-escalation"  # iam:CreateUser
must_flag  "$OUT" iamsts   "policystatements-no-escalation"  # sts:AssumeRole (service-prefix subsumption)
must_flag  "$OUT" iammulti "policystatements-no-escalation"  # escalation hidden in a 2nd service

# platformTrust.clusterRoles (ADR-081) — only platform-OWNED Teams may bind cluster-scoped read roles.
OUT="$(run_env resources-platformtrust.yaml values-platformtrust.yaml)"
must_admit "$OUT" ptok                                                    # role ∈ the platform team's allowlist
must_admit "$OUT" ptnone                                                  # no request → precondition skips the rule
must_flag  "$OUT" ptbadrole "platformtrust-clusterroles-within-envelope"  # role ∉ allowlist

# Self-service cloud resources (ADR-073) — engine ∈ allowedEngines + count ≤ maxPerEnvironment. Team alpha opted
# in to s3, cap 2.
OUT="$(run_env resources-s3.yaml values-resources-s3.yaml)"
must_admit "$OUT" okrsrc                                         # 2 s3, both allowed, within cap
must_admit "$OUT" norsrc                                         # no resources → no-op (regression safety)
must_flag  "$OUT" badengine "resources-engine-within-envelope"  # engine sqs ∉ [s3]
must_flag  "$OUT" overcount "resources-count-within-cap"         # 3 > cap 2
# DEFAULT-DENY: the same resource-bearing claims against a Team with an EMPTY resources envelope (the CRD-
# defaulted state) must be rejected — engine ∉ [] and count > 0.
OUT="$(run_env resources-s3.yaml values-resources-noenv.yaml)"
must_flag  "$OUT" okrsrc "resources-engine-within-envelope"     # s3 ∉ [] (default-deny)
must_flag  "$OUT" badengine "resources-count-within-cap"        # any count > 0
must_admit "$OUT" norsrc                                         # still a no-op with no resources

echo "environment-envelope policy checks passed (tier/stage/residency/quota/team-existence/team-product/customer/iam/resources)."
