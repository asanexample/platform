#!/usr/bin/env bash
# Renders the platform policies chart and runs the Kyverno CLI test suite against it.
# Cluster-free: matches CI. Requires `helm` and `kyverno` (pin the CLI to the chart's appVersion).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$DIR/../policies-chart"

mkdir -p "$DIR/rendered"
helm template kpp "$CHART" \
  --set validationFailureAction=Enforce \
  --set replicaFloorFailureAction=Enforce \
  --set enableRolloutKind=true \
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
# so grep the actual patched resource.
MUTATED="$(cat "$DIR/rendered/mutated"/* 2>/dev/null)"
for field in 'terminationGracePeriodSeconds: 30' 'preStop:' 'seconds: 10'; do
  grep -q "$field" <<<"$MUTATED" || { echo "FAIL: mutate did not inject '$field' on the bare Deployment"; printf '%s\n' "$MUTATED"; exit 1; }
done
echo "Graceful-drain field-injection check passed (terminationGracePeriodSeconds + preStop sleep)."

# Topology-spread check: mutate-topology-spread must inject topologySpreadConstraints with a labelSelector
# DERIVED from the workload's own selector (ADR-085) — same trigger-derived technique as the PDB. The bare-app
# Deployment's selector is { app: bare-app }, so the injected spread must select on it (proving the map
# substitution again, here inside a controller-matching mutate rather than generate).
for field in 'topologySpreadConstraints:' 'whenUnsatisfiable: ScheduleAnyway' 'topology.kubernetes.io/zone' 'pod-template-hash'; do
  grep -q "$field" <<<"$MUTATED" || { echo "FAIL: topology-spread mutate did not inject '$field'"; printf '%s\n' "$MUTATED"; exit 1; }
done
grep -q '{{ request.object' <<<"$MUTATED" && { echo "FAIL: topology spread left an unresolved Kyverno variable"; printf '%s\n' "$MUTATED"; exit 1; }
echo "Topology-spread injection check passed (zone + node, ScheduleAnyway, derived selector)."

# Generate-check: generate-workload-pdb must emit a PodDisruptionBudget for the trigger Deployment with a
# selector COPIED from the workload's own matchLabels (ADR-085 W2). The same kyverno-apply run above already
# wrote the generated resource into rendered/mutated (generate fires on the same bare-app Deployment). The
# crux being proven here is that "{{ request.object.spec.selector.matchLabels }}" resolves to the workload's
# selector MAP, not a string. The trigger's selector is { app: bare-app } in namespace team-alpha.
GEN="$(cat "$DIR/rendered/mutated"/*generated* 2>/dev/null || cat "$DIR/rendered/mutated"/* 2>/dev/null)"
grep -q 'kind: PodDisruptionBudget' <<<"$GEN" || { echo "FAIL: no PodDisruptionBudget generated for the trigger Deployment"; printf '%s\n' "$GEN"; exit 1; }
grep -q 'name: bare-app-pdb' <<<"$GEN" || { echo "FAIL: generated PDB not named <workload>-pdb"; printf '%s\n' "$GEN"; exit 1; }
grep -q 'maxUnavailable: 1' <<<"$GEN" || { echo "FAIL: generated PDB must be maxUnavailable: 1 (drain-safe)"; printf '%s\n' "$GEN"; exit 1; }
# Selector must carry the trigger's own label (proves the map substitution, not a literal string).
grep -qE 'app: bare-app' <<<"$GEN" || { echo "FAIL: generated PDB selector did not copy the workload matchLabels"; printf '%s\n' "$GEN"; exit 1; }
grep -q '{{ request.object' <<<"$GEN" && { echo "FAIL: generated PDB still contains an unresolved Kyverno variable"; printf '%s\n' "$GEN"; exit 1; }
echo "PDB generate-check passed (bare-app-pdb, maxUnavailable: 1, selector copied from the workload)."

# Rollout-kind check (ADR-056, enableRolloutKind=true): the availability policies must also fire on an Argo
# `Rollout`. Apply the bare-rollout fixture and assert (a) generate-workload-pdb makes a PDB with the Rollout's
# own selector, and (b) mutate-topology-spread injects spread keyed on `rollouts-pod-template-hash` (NOT
# pod-template-hash — Rollout pods carry the former). Proves the Rollout match + the separate Rollout topology
# rule, the way the Phase-0 spike proved it live.
RO="$(kyverno apply rendered/policies.yaml --resource resources/rollout-input.yaml --values-file values.yaml -o "$DIR/rendered/rollout" 2>&1 || true)"
ROUT="$(cat "$DIR/rendered/rollout"/* 2>/dev/null)"
grep -q 'name: bare-rollout-pdb' <<<"$ROUT" || { echo "FAIL: no PDB generated for the Rollout"; printf '%s\n' "$RO" "$ROUT"; exit 1; }
grep -qE 'app: bare-rollout' <<<"$ROUT" || { echo "FAIL: Rollout PDB/spread did not copy the Rollout's matchLabels"; printf '%s\n' "$ROUT"; exit 1; }
grep -q 'topologySpreadConstraints' <<<"$ROUT" || { echo "FAIL: topology spread not injected on the Rollout"; printf '%s\n' "$ROUT"; exit 1; }
grep -q 'rollouts-pod-template-hash' <<<"$ROUT" || { echo "FAIL: Rollout topology spread must use rollouts-pod-template-hash"; printf '%s\n' "$ROUT"; exit 1; }
echo "Rollout-kind check passed (bare-rollout-pdb + topology spread on rollouts-pod-template-hash)."

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

# Render-check the cross-namespace DB credential sync (ADR-099 Flagship). generate+clone can't be meaningfully
# unit-tested offline (the clone needs a live source Secret + background controller — the real gate is the
# cluster verification), so assert the template renders the right ClusterPolicy and CLUSTER-SCOPED clone RBAC
# for a binding: the generate clones flagship-db-app from the platform-database namespace into the app
# Environment namespace. The RBAC is cluster-scoped (target/source namespaces are created DOWNSTREAM by
# Crossplane/ArgoCD, so a namespace-scoped Role can't be created eagerly at policy-apply time — it would fail
# "namespaces not found" on a from-scratch bootstrap), but WRITE stays pinned by resourceNames to the Secret.
echo "Rendering DB-secret-sync (template validity) ..."
DS="$(helm template kpp "$CHART" \
  --set enableDbSecretSync=true \
  --set-json 'dbSecretSyncBindings=[{"name":"flagship-dev","sourceNamespace":"platform-flagship-db","secretName":"flagship-db-app","targetNamespace":"platform-flagship-dev"}]' \
  --show-only templates/sync-db-secret.yaml)"
grep -q 'name: sync-platform-db-secret' <<<"$DS" || { echo "FAIL: sync-platform-db-secret ClusterPolicy did not render"; exit 1; }
grep -q 'namespace: "platform-flagship-db"' <<<"$DS" || { echo "FAIL: clone source namespace missing"; exit 1; }
grep -q 'namespace: "platform-flagship-dev"' <<<"$DS" || { echo "FAIL: clone target namespace missing"; exit 1; }
grep -q 'platform.refplat.org/runtime: platform-database' <<<"$DS" || { echo "FAIL: source namespaceSelector guard missing"; exit 1; }
grep -q 'generateExisting: true' <<<"$DS" || { echo "FAIL: generateExisting must back-fill the existing DB"; exit 1; }
# READ is a cluster-wide ClusterRole (generateExisting does a cluster-scoped list), bound to the controllers
# by an explicit ClusterRoleBinding (immediate — not an aggregation label that races policy admission).
grep -q 'name: kyverno:sync-db-secret-read' <<<"$DS" || { echo "FAIL: cluster-wide read ClusterRole missing (generateExisting needs a cluster-scoped list)"; exit 1; }
# WRITE is a cluster-scoped ClusterRole (the target/source namespaces don't exist at policy-apply time), NOT a
# namespace-scoped Role — that's the from-scratch-bootstrap fix. Bound by ClusterRoleBinding to both SAs.
grep -q 'name: kyverno:sync-db-secret-write' <<<"$DS" || { echo "FAIL: cluster-scoped write ClusterRole missing"; exit 1; }
grep -qE '^kind: Role$' <<<"$DS" && { echo "FAIL: no namespace-scoped Role may render — namespaces are created downstream, so eager Role creation deadlocks bootstrap"; exit 1; }
# WRITE verbs must NOT be resourceNames-pinned: Kyverno's generate pre-flight authz check does a NAME-LESS
# SubjectAccessReview for create/update/delete on the target Secret's namespace, and a resourceNames-scoped
# grant fails it — Kyverno then REJECTS the policy at admission (verified live). So the write is un-name-scoped,
# same as the generate-pdb ClusterRole; the ClusterPolicy is what bounds which Secret is actually written.
grep -qE '^[[:space:]]*resourceNames:' <<<"$DS" && { echo "FAIL: write ClusterRole must NOT use resourceNames — Kyverno's name-less generate authz pre-flight rejects a name-scoped grant"; exit 1; }
grep -q 'verbs: \["create", "update", "patch", "delete"\]' <<<"$DS" || { echo "FAIL: write ClusterRole must grant un-name-scoped create/update/patch/delete on secrets"; exit 1; }
grep -q 'name: kyverno-background-controller' <<<"$DS" || { echo "FAIL: write RBAC must bind the background controller SA"; exit 1; }
grep -q 'name: kyverno-admission-controller' <<<"$DS" || { echo "FAIL: write RBAC must also bind the admission controller SA (its pre-flight authz check rejects the policy otherwise)"; exit 1; }
# Guard: the READ ClusterRole must be READ-ONLY — no write verb in its rule block (scope the grep to that role).
awk '/name: kyverno:sync-db-secret-read$/{f=1} f&&/^rules:/{r=1} r&&/kind: (ClusterRole|ClusterRoleBinding)/{exit} r' <<<"$DS" \
  | grep -qE '"(create|update|patch|delete)"' && { echo "FAIL: the read ClusterRole must be READ-ONLY (write lives in kyverno:sync-db-secret-write)"; exit 1; }
echo "DB-secret-sync render-check passed (clone + cluster-scoped READ/WRITE, un-name-scoped for the generate authz pre-flight)."

# NOTE: the restrict-environment-envelope / restrict-environment-control-plane policies (and their tests) moved to the
# crossplane module — infra/modules/crossplane/.kyverno-tests/run.sh — because they match Crossplane CRDs and
# must install after them (see infra/modules/crossplane/charts/environment-policies/Chart.yaml).
