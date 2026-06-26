#!/usr/bin/env bash
# Unit test for validate-releases.sh (ADR-071). Self-contained: builds a throwaway HEAD checkout with one
# Environment claim (alpha/shop/dev, declaring Services web+api) and various Release files, runs the validator
# with RELEASE_FILES, and asserts the exit code. Run: bash .github/scripts/gitops-gate/test-validate-releases.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/validate-releases.sh"
command -v yq >/dev/null 2>&1 || { echo "::error::yq required"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
head="${work}/head"
relroot="${head}/gitops/releases/alpha/shop"
envroot="${head}/gitops/environments/alpha/shop"
mkdir -p "$relroot" "$envroot"

# The join authority: an Environment claim declaring Services web + api.
cat >"${envroot}/dev.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata: { name: alpha-shop-dev }
spec:
  team: alpha
  product: shop
  stage: dev
  services:
    web: {}
    api: {}
Y

# Platform agent (ADR-082): an XAgent claim at gitops/agents/<product>.yaml is ALSO a valid Release target
# (agents are XAgents, not XEnvironments). Note the agent's name (copilot) differs from the release name.
mkdir -p "${head}/gitops/agents"
cat >"${head}/gitops/agents/copilot.yaml" <<'Y'
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata: { name: copilot }
spec: { product: copilot }
Y

D1="sha256:69ff1ab2abeb52b7fde3fec3b75e548116a7d33a27816bf2afd36df1f93527a7"

pass=0; failc=0
# run <expect: ok|deny> <name> <release-rel-path> <body>
# Writes the body to the given release path (the path is load-bearing — the validator joins the release
# gitops/releases/<t>/<p>/<file> to its SIBLING Environment gitops/environments/<t>/<p>/<file>), runs the
# validator targeting it, and asserts the exit code.
run() {
  local expect="$1" name="$2" relpath="$3" body="$4"
  mkdir -p "${head}/$(dirname "$relpath")"
  printf '%s\n' "$body" >"${head}/${relpath}"
  BASE_DIR="$head" HEAD_DIR="$head" RELEASE_FILES="$relpath" bash "$script" >/dev/null 2>&1
  local rc=$?; local got=ok; [ $rc -ne 0 ] && got=deny
  rm -f "${head}/${relpath}"
  if [ "$got" = "$expect" ]; then echo "  ✓ ${name} (${got})"; pass=$((pass+1));
  else echo "  ✗ ${name}: expected ${expect}, got ${got}"; failc=$((failc+1)); fi
}

echo "== validate-releases.sh =="
# The release filename mirrors its sibling Environment (dev.yaml ↔ environments/.../dev.yaml).
run ok   "valid digest bump" gitops/releases/alpha/shop/dev.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: alpha-shop-dev }
spec: { environmentRef: alpha-shop-dev, services: { web: { digest: "${D1}" } } }
Y
)"
run deny "rejects a mutable tag (not digest)" gitops/releases/alpha/shop/dev.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: alpha-shop-dev }
spec: { environmentRef: alpha-shop-dev, services: { web: { digest: "v1.2.3" } } }
Y
)"
run deny "rejects missing environmentRef" gitops/releases/alpha/shop/dev.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: alpha-shop-dev }
spec: { services: { web: { digest: "${D1}" } } }
Y
)"
run deny "rejects environmentRef mismatch" gitops/releases/alpha/shop/dev.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: alpha-shop-dev }
spec: { environmentRef: alpha-shop-prod, services: { web: { digest: "${D1}" } } }
Y
)"
run deny "rejects a Service not declared on the Env" gitops/releases/alpha/shop/dev.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: alpha-shop-dev }
spec: { environmentRef: alpha-shop-dev, services: { worker: { digest: "${D1}" } } }
Y
)"
run deny "rejects empty services" gitops/releases/alpha/shop/dev.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: alpha-shop-dev }
spec: { environmentRef: alpha-shop-dev, services: {} }
Y
)"
# No sibling Environment claim at this path (prod.yaml has no environments/.../prod.yaml) → dangling join.
run deny "rejects a dangling Environment join" gitops/releases/alpha/shop/prod.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: alpha-shop-prod }
spec: { environmentRef: alpha-shop-prod, services: { web: { digest: "${D1}" } } }
Y
)"
# ADR-082: a platform agent's Release has no sibling Environment, but a sibling Agent claim
# (gitops/agents/copilot.yaml) — accepted. The path ties release→agent; environmentRef isn't matched against an
# Environment name (the agent is named differently). This is the regression #732/#733 exposed.
run ok   "accepts an Agent-targeted release (agent claim, no Environment)" gitops/releases/platform/copilot/dev.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: platform-copilot-dev }
spec: { environmentRef: platform-copilot-dev, services: { server: { digest: "${D1}" } } }
Y
)"
# But a Release with NEITHER a sibling Environment NOR an Agent claim is still a dangling target → deny.
run deny "rejects a release with no Environment and no Agent" gitops/releases/platform/ghost/dev.yaml "$(cat <<Y
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: platform-ghost-dev }
spec: { environmentRef: platform-ghost-dev, services: { server: { digest: "${D1}" } } }
Y
)"

echo "${pass} passed, ${failc} failed"
[ "$failc" -eq 0 ]
