#!/usr/bin/env bash
# Renders the crossplane agent-policies chart and tests its Kyverno ClusterPolicies (restrict-agent-envelope +
# restrict-agent-control-plane) — the XAgent admission gate (ADR-082 D6). Cluster-free: matches CI. Requires
# `helm` and `kyverno` (pin the CLI to the chart appVersion). Sibling of run.sh (the environment policies).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$DIR/../charts/agent-policies"
mkdir -p "$DIR/rendered"

# restrict-agent-control-plane — render-validity (the deny rule reads request.userInfo, unmockable offline).
echo "Rendering agent-control-plane policy (template validity) ..."
CPPOL="$DIR/rendered/agent-control-plane.yaml"
helm template kap "$CHART" --show-only templates/agent-control-plane.yaml >"$CPPOL"
grep -q 'name: restrict-agent-control-plane' "$CPPOL"            || { echo "FAIL: control-plane policy did not render"; exit 1; }
grep -q 'platform.refplat.org/v1beta1/XAgent' "$CPPOL"          || { echo "FAIL: control-plane must match XAgent"; exit 1; }
grep -q 'system:serviceaccount:crossplane-system:\*' "$CPPOL"   || { echo "FAIL: control-plane must skip crossplane-system principals"; exit 1; }
echo "agent-control-plane render-check passed."

# restrict-agent-envelope — behavioral (kyverno apply; no apiCalls, so it unit-tests offline).
echo "Testing agent-envelope policy (the awsPermissions deny-set + placement) ..."
ENVPOL="$DIR/rendered/agent-envelope.yaml"
helm template kap "$CHART" --set enableAgentEnvelope=true --show-only templates/agent-envelope.yaml >"$ENVPOL"
AD="$DIR/agent-envelope"
apply() { kyverno apply "$ENVPOL" --resource "$AD/$1" 2>&1 || true; }

OUT="$(apply clean.yaml)"
grep -q 'pass: 2' <<<"$OUT" || { echo "FAIL: a clean XAgent (benign s3, hub placement) must pass both rules"; printf '%s\n' "$OUT"; exit 1; }

OUT="$(apply escalate.yaml)"
grep -q 'policystatements-no-escalation' <<<"$OUT" || { echo "FAIL: an XAgent requesting iam/sts must be denied by the deny-set"; printf '%s\n' "$OUT"; exit 1; }

OUT="$(apply badplacement.yaml)"
grep -q 'placement-hub-only' <<<"$OUT" || { echo "FAIL: an XAgent placed off the hub must be denied"; printf '%s\n' "$OUT"; exit 1; }

echo "agent-envelope checks passed (deny-set rejects iam/sts escalation; placement hub-only; benign admitted)."
echo "Agent policy checks passed (ADR-082 D6 — the XAgent admission gate)."
