#!/usr/bin/env bash
# Renders the crossplane service-grant-policies chart and tests its ClusterPolicy restrict-service-grant-
# admission (ADR-101) — the ServiceGrant admission gate. Cluster-free: matches CI. Requires `helm` and
# `kyverno` (pin the CLI to the chart appVersion). Sibling of run-agents.sh (the XAgent admission gate).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$DIR/../charts/service-grant-policies"
mkdir -p "$DIR/rendered"

# deny-non-platform-service-grant — render-validity only (the deny rule reads request.userInfo, which kyverno
# apply can't mock offline without an impersonation flag this harness doesn't use — same treatment as
# restrict-agent-control-plane in run-agents.sh).
echo "Rendering restrict-service-grant-admission (template validity: RBAC rule) ..."
POL="$DIR/rendered/service-grant-admission.yaml"
helm template ksp "$CHART" --show-only templates/service-grant-admission.yaml >"$POL"
grep -q 'name: restrict-service-grant-admission'         "$POL" || { echo "FAIL: policy did not render"; exit 1; }
grep -q 'platform.refplat.org/v1beta1/ServiceGrant'       "$POL" || { echo "FAIL: must match ServiceGrant"; exit 1; }
grep -q 'system:serviceaccount:crossplane-system:\*'      "$POL" || { echo "FAIL: must skip crossplane-system principals (the allow-list)"; exit 1; }
grep -q 'name: deny-non-platform-service-grant'           "$POL" || { echo "FAIL: RBAC rule missing"; exit 1; }
grep -q 'name: deny-regulated-tier-service-grant'         "$POL" || { echo "FAIL: regulated-tier rule missing"; exit 1; }
echo "restrict-service-grant-admission render-check passed (RBAC rule)."

# deny-regulated-tier-service-grant — behavioral (kyverno apply against a mocked xenvironments apiCall; no
# userInfo dependency, so it unit-tests offline). The RBAC rule above also evaluates on these `apply` calls and
# errors (unmockable request.userInfo) — expected noise, not asserted on; only this rule's verdict is checked.
echo "Testing deny-regulated-tier-service-grant (the hipaa/pci exclusion) ..."
SD="$DIR/service-grant-admission"

OUT="$(kyverno apply "$POL" --resource "$SD/resources.yaml" --values-file "$SD/values.yaml" 2>&1 || true)"
grep -q 'ServiceGrant/clean failed'          <<<"$OUT" && { echo "FAIL: clean (standard-tier both sides) must NOT be denied by deny-regulated-tier-service-grant"; printf '%s\n' "$OUT"; exit 1; }
grep -q 'ServiceGrant/regulatedtarget failed' <<<"$OUT" || { echo "FAIL: regulated TARGET tier (hipaa) must be denied"; printf '%s\n' "$OUT"; exit 1; }
grep -q 'ServiceGrant/regulatedsubject failed' <<<"$OUT" || { echo "FAIL: regulated SUBJECT tier (pci) must be denied"; printf '%s\n' "$OUT"; exit 1; }

echo "deny-regulated-tier-service-grant checks passed (standard admitted; hipaa/pci target OR subject denied)."
echo "ServiceGrant policy checks passed (ADR-101 — the ServiceGrant admission gate)."
