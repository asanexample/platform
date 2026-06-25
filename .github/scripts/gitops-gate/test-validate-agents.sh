#!/usr/bin/env bash
# Unit test for validate-agents.sh (ADR-082) — cluster-free, runs in CI alongside the other gitops-gate tests.
# Builds tiny XAgent + Product fixtures in a temp tree and asserts the validator's verdicts. Requires yq (mikefarah).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$HERE/validate-agents.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/gitops/agents" "$T/gitops/products/platform"

cat > "$T/gitops/products/platform/triage-copilot.yaml" <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata: { name: platform-triage-copilot }
spec: { team: platform, repo: asanexample/platform-triage-copilot }
EOF

mk() { cat > "$T/gitops/agents/$1.yaml"; }
run() { BASE_DIR="$T" HEAD_DIR="$T" AGENT_FILES="gitops/agents/$1.yaml" bash "$VALIDATOR" 2>/dev/null; }

fail=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "::error::test-validate-agents: $1" >&2; fail=1; }

# 1. a clean obs-read agent → pass
mk good <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata: { name: triage-copilot }
spec: { team: platform, product: triage-copilot, placement: { cluster: platform }, model: { provider: bedrock, id: us.anthropic.claude-sonnet-4-6 }, obsRead: true }
EOF
run good && ok "clean agent passes" || bad "clean agent should pass"

# 2. iam/sts escalation in awsPermissions → fail
mk escalate <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata: { name: triage-copilot }
spec: { team: platform, product: triage-copilot, awsPermissions: { policyStatements: [ { actions: ["sts:AssumeRole"], resources: ["*"] } ] } }
EOF
run escalate && bad "iam/sts escalation should fail" || ok "iam/sts escalation rejected (deny-set)"

# 3. off-hub placement → fail
mk offhub <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata: { name: triage-copilot }
spec: { team: platform, product: triage-copilot, placement: { cluster: preprod } }
EOF
run offhub && bad "off-hub placement should fail" || ok "off-hub placement rejected"

# 4. missing owning Product → fail
mk ghost <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata: { name: ghost }
spec: { team: platform, product: nonexistent }
EOF
run ghost && bad "missing Product should fail" || ok "missing owning Product rejected"

# 5. bedrock without a pinned model id → fail
mk nomodel <<'EOF'
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata: { name: triage-copilot }
spec: { team: platform, product: triage-copilot, model: { provider: bedrock } }
EOF
run nomodel && bad "unpinned bedrock model should fail" || ok "unpinned bedrock model rejected"

[ "$fail" -eq 0 ] && echo "validate-agents tests passed." || { echo "validate-agents tests FAILED."; exit 1; }
