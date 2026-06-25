#!/usr/bin/env bash
# Offline `crossplane render` test for the Agent Composition (ADR-082). Runs the Pipeline functions via Docker
# and asserts the rendered agent runtime slot — no cluster. Mirrors .environment-api-tests/render.sh. Requires
# crossplane + docker; runs as its own CI job ("Agent Composition Render").
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
comp="${here}/../charts/agent-api/files/composition.yaml"
fns="${here}/render/functions.yaml"
agentcfg="${here}/render/agentconfig.yaml"

command -v crossplane >/dev/null 2>&1 || { echo "::error::crossplane CLI not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "::error::docker is required for crossplane render"; exit 1; }

render() { crossplane render "$1" "$comp" "$fns" --extra-resources "$agentcfg" 2>/dev/null; }

echo "== render triage-copilot (active, obs-read) → ns + SA + Pod-Identity (bedrock) + obs-read binding =="
OUT="$(render "${here}/agents/triage-copilot.yaml")"
printf '%s' "$OUT" | grep -q 'name: platform-agent-triage-copilot$'              || { echo "::error::namespace platform-agent-triage-copilot not rendered"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'platform.refplat.org/runtime: platform-agent'      || { echo "::error::platform-agent runtime label missing"; exit 1; }
printf '%s' "$OUT" | grep -q 'kind: ServiceAccount'                              || { echo "::error::ServiceAccount not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'external-name: Pod-platform-agent-triage-copilot'  || { echo "::error::Pod-Identity role Pod-platform-agent-triage-copilot not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'permissionsBoundary'                              || { echo "::error::minted role missing the permissions boundary"; exit 1; }
printf '%s' "$OUT" | grep -q 'bedrock:InvokeModel'                              || { echo "::error::model grant missing bedrock:InvokeModel"; exit 1; }
printf '%s' "$OUT" | grep -q 'bedrock:Converse'                                 || { echo "::error::model grant missing bedrock:Converse"; exit 1; }
printf '%s' "$OUT" | grep -qE 'inference-profile/\*'                            || { echo "::error::bedrock grant must scope to the cross-region inference profiles"; exit 1; }
# The grant is DATA-PLANE only — no management actions.
printf '%s' "$OUT" | grep -qE 'bedrock:(Create|Delete|Put|Update|Tag)'         && { echo "::error::Bedrock grant must be data-plane only (no management actions)"; exit 1; } || true
printf '%s' "$OUT" | grep -q 'kind: PodIdentityAssociation'                     || { echo "::error::PodIdentityAssociation not rendered (active agent)"; exit 1; }
printf '%s' "$OUT" | grep -q 'serviceAccount: triage-copilot'                   || { echo "::error::Pod-Identity association must bind the agent SA"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: platform-agent-triage-copilot-obsread'      || { echo "::error::obs-read ClusterRoleBinding not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'name: platform-trust-observability-reader'        || { echo "::error::obs-read binding must reference platform-trust-observability-reader"; exit 1; }
# obs-read binds the NAMED SA, not the whole namespace's SAs (tighter than the tenant platform-trust binding).
printf '%s' "$OUT" | grep -A20 'name: platform-agent-triage-copilot-obsread' | grep -A2 'subjects:' | grep -q 'kind: ServiceAccount' || { echo "::error::obs-read binding must target the named ServiceAccount subject"; exit 1; }
echo "  ✓ triage-copilot OK (ns + SA + Pod-Identity role/policy/association with data-plane bedrock + boundary; obs-read CRB → named SA)"

echo "== render triage-copilot-suspended (kill-switch) → NO PodIdentityAssociation, slot retained =="
OUT="$(render "${here}/agents/triage-copilot-suspended.yaml")"
printf '%s' "$OUT" | grep -q 'kind: PodIdentityAssociation'                     && { echo "::error::suspended agent must NOT render a PodIdentityAssociation (Bedrock hard-stop) — kill-switch broken"; exit 1; } || true
printf '%s' "$OUT" | grep -q 'name: platform-agent-triage-copilot$'             || { echo "::error::suspended agent must retain its namespace/slot (reversible)"; exit 1; }
printf '%s' "$OUT" | grep -q 'kind: Role'                                       || { echo "::error::suspended agent should retain the (inert) IAM role"; exit 1; }
echo "  ✓ suspended OK (PodIdentityAssociation removed → no Bedrock; ns/SA/role retained, reversible)"

echo "Agent Composition render checks passed (ADR-082 — slot provisioning, data-plane bedrock identity, obs-read binding, kill-switch)."
