#!/usr/bin/env bash
# Offline `crossplane render` test for the ServiceGrant Composition (ADR-101). Runs the Pipeline functions via
# Docker and asserts EXACTLY two CiliumNetworkPolicy halves render, with correct namespaces/selectors/ports —
# and the L7 http narrowing (or its absence) is byte-correct on both halves. No cluster. Mirrors
# .agent-api-tests/render.sh. Requires crossplane + docker; runs as its own CI job ("ServiceGrant Composition
# Render").
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
comp="${here}/../charts/service-grant-api/files/composition.yaml"
fns="${here}/render/functions.yaml"

command -v crossplane >/dev/null 2>&1 || { echo "::error::crossplane CLI not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "::error::docker is required for crossplane render"; exit 1; }

render() { crossplane render "$1" "$comp" "$fns" 2>/dev/null; }

echo "== render l4-only (no capability.network.http) → flat L4-only toPorts, no rules.http anywhere =="
OUT="$(render "${here}/service-grants/l4-only.yaml")"
# exactly two composed CiliumNetworkPolicy Objects
[ "$(printf '%s' "$OUT" | grep -c 'kind: CiliumNetworkPolicy')" -eq 2 ] || { echo "::error::expected exactly 2 CiliumNetworkPolicy objects"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -q 'composition-resource-name: cnp-egress'  || { echo "::error::cnp-egress not rendered"; exit 1; }
printf '%s' "$OUT" | grep -q 'composition-resource-name: cnp-ingress' || { echo "::error::cnp-ingress not rendered"; exit 1; }
# egress half: subject namespace, subject app selector, DNS block, target ns+app toEndpoints, granted port
printf '%s' "$OUT" | grep -q 'namespace: alpha-shop-dev'          || { echo "::error::egress CNP must live in the subject namespace alpha-shop-dev"; exit 1; }
printf '%s' "$OUT" | grep -A40 'name: allow-intake-bravo-egress' | grep -q 'app: orders' || { echo "::error::egress endpointSelector must match app: orders (the subject service)"; exit 1; }
printf '%s' "$OUT" | grep -q 'k8s:io.kubernetes.pod.namespace: kube-system' || { echo "::error::egress must carry the kube-dns DNS block"; exit 1; }
printf '%s' "$OUT" | grep -q 'k8s:k8s-app: kube-dns'                        || { echo "::error::egress DNS block missing k8s-app: kube-dns"; exit 1; }
printf '%s' "$OUT" | grep -q 'namespace: bravo-dispatch-dev'                || { echo "::error::ingress CNP must live in the target namespace bravo-dispatch-dev"; exit 1; }
# ingress half: fromEndpoints matches BOTH subject namespace AND subject app (tighter than namespace-only)
printf '%s' "$OUT" | grep -A6 'fromEndpoints:' | grep -q 'app: orders'                                  || { echo "::error::ingress fromEndpoints must match app: orders (not namespace-only)"; exit 1; }
printf '%s' "$OUT" | grep -A6 'fromEndpoints:' | grep -q 'k8s:io.kubernetes.pod.namespace: alpha-shop-dev' || { echo "::error::ingress fromEndpoints must match the subject namespace alpha-shop-dev"; exit 1; }
# both halves carry the granted L4 port/protocol
[ "$(printf '%s' "$OUT" | grep -c 'port: "8080"')" -ge 2 ] || { echo "::error::both CNP halves must carry port 8080"; exit 1; }
[ "$(printf '%s' "$OUT" | grep -c 'protocol: TCP')" -ge 2 ] || { echo "::error::both CNP halves must carry protocol TCP"; exit 1; }
# backward-compat: NO rules.http anywhere in this render (no capability.network.http was set)
printf '%s' "$OUT" | grep -qE '^\s+http:' && { echo "::error::l4-only grant must not render an http: rules block anywhere"; printf '%s\n' "$OUT"; exit 1; } || true
# ownership: both composed resources are owned by the ServiceGrant XR (normal Crossplane GC on delete)
[ "$(printf '%s' "$OUT" | grep -c 'kind: ServiceGrant')" -ge 3 ] || { echo "::error::expected ownerReferences to ServiceGrant on both composed resources (+ the XR itself)"; exit 1; }
echo "  ✓ l4-only OK (2 CNPs; egress in alpha-shop-dev app:orders; ingress in bravo-dispatch-dev fromEndpoints ns+app; port 8080/TCP both halves; no rules.http; ServiceGrant-owned)"

echo "== render l7-http (capability.network.http set) → toPorts[].rules.http on BOTH halves =="
OUT="$(render "${here}/service-grants/l7-http.yaml")"
[ "$(printf '%s' "$OUT" | grep -c 'kind: CiliumNetworkPolicy')" -eq 2 ] || { echo "::error::expected exactly 2 CiliumNetworkPolicy objects"; printf '%s\n' "$OUT"; exit 1; }
[ "$(printf '%s' "$OUT" | grep -c '^\s*http:$')" -eq 2 ] || { echo "::error::expected exactly 2 rules.http blocks (one per CNP half)"; printf '%s\n' "$OUT"; exit 1; }
[ "$(printf '%s' "$OUT" | grep -c 'method: POST')" -eq 2 ]        || { echo "::error::both halves must carry method: POST"; exit 1; }
[ "$(printf '%s' "$OUT" | grep -c 'path: /shipments')" -eq 2 ]    || { echo "::error::both halves must carry path: /shipments"; exit 1; }
# the L7 rule still carries the L4 port alongside (narrowing, not replacing, the port)
[ "$(printf '%s' "$OUT" | grep -c 'port: "8080"')" -ge 2 ] || { echo "::error::L7-narrowed halves must still carry port 8080"; exit 1; }
echo "  ✓ l7-http OK (2 CNPs; rules.http{method:POST,path:/shipments} on BOTH halves, alongside the L4 port)"

echo "== render l4-authenticated (capability.network.authentication.mode: required) → ingress-half-only authentication =="
OUT="$(render "${here}/service-grants/l4-authenticated.yaml")"
[ "$(printf '%s' "$OUT" | grep -c 'kind: CiliumNetworkPolicy')" -eq 2 ] || { echo "::error::expected exactly 2 CiliumNetworkPolicy objects"; printf '%s\n' "$OUT"; exit 1; }
# ingress half (allow-orders-alpha-to-intake-ingress) carries authentication: mode: required
printf '%s' "$OUT" | grep -A20 'name: allow-orders-alpha-to-intake-ingress' | grep -q 'authentication:' || { echo "::error::ingress half must carry an authentication block"; printf '%s\n' "$OUT"; exit 1; }
printf '%s' "$OUT" | grep -A20 'name: allow-orders-alpha-to-intake-ingress' | grep -q 'mode: required'  || { echo "::error::ingress half's authentication.mode must be required"; exit 1; }
# egress half (allow-intake-bravo-egress) must NOT carry any authentication block — auth lives on ingress only
printf '%s' "$OUT" | grep -A20 'name: allow-intake-bravo-egress' | grep -q 'authentication:' && { echo "::error::egress half must NOT carry an authentication block"; printf '%s\n' "$OUT"; exit 1; } || true
echo "  ✓ l4-authenticated OK (ingress half carries authentication.mode: required; egress half does not)"

echo "== render l4-only + l4-second-target-same-subject together (same subject, two different target services in the same target namespace) → two DISTINCTLY-named ingress CNPs, neither clobbers the other =="
OUT1="$(render "${here}/service-grants/l4-only.yaml")"
OUT2="$(render "${here}/service-grants/l4-second-target-same-subject.yaml")"
printf '%s' "$OUT1" | grep -q 'name: allow-orders-alpha-to-intake-ingress'    || { echo "::error::l4-only must render ingress CNP allow-orders-alpha-to-intake-ingress"; printf '%s\n' "$OUT1"; exit 1; }
printf '%s' "$OUT2" | grep -q 'name: allow-orders-alpha-to-shipments-ingress' || { echo "::error::l4-second-target-same-subject must render ingress CNP allow-orders-alpha-to-shipments-ingress"; printf '%s\n' "$OUT2"; exit 1; }
# the two ingress CNP names must differ even though both grants share the exact same subject
[ "$(printf '%s' "$OUT1" | grep -oE 'allow-orders-alpha-to-[a-z-]+-ingress')" != "$(printf '%s' "$OUT2" | grep -oE 'allow-orders-alpha-to-[a-z-]+-ingress')" ] \
  || { echo "::error::the two ingress CNP names must differ (target.service must appear in the name) — a collision here means one grant's ingress rule silently clobbers the other in-cluster"; exit 1; }
printf '%s' "$OUT2" | grep -A20 'name: allow-orders-alpha-to-shipments-ingress' | grep -q 'app: shipments' || { echo "::error::the shipments ingress CNP's endpointSelector must match app: shipments"; printf '%s\n' "$OUT2"; exit 1; }
echo "  ✓ multi-target-same-subject OK (allow-orders-alpha-to-intake-ingress != allow-orders-alpha-to-shipments-ingress; each endpointSelector matches its own target service)"

echo "ServiceGrant Composition render checks passed (ADR-101 — exactly 2 CNPs; L4-only backward-compat; L7 Envoy narrowing on both halves; mutual-auth on the ingress half only; distinct ingress names for multi-target same-subject grants)."
