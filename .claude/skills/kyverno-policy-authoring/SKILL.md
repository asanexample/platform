---
name: kyverno-policy-authoring
description: >-
  How to author and edit the Kyverno ClusterPolicies in this platform's `policy`
  module (the PRODUCER side of policy). Use when adding or changing a cluster-wide
  admission guardrail (RBAC hardening, default-namespace, image floor, resource/
  probe/label requirements, PSA backstops), a per-product supply-chain policy
  (cosign verify-images / verify-attestations), or a per-cluster knob
  (validationFailureAction, compliance_tier, the Audit→Enforce flip); and when
  testing or debugging those policies. Covers the policies-chart layout, the Helm
  helpers, values projection, per-product derivation from the Product registry, the
  ADR-046 split with the Crossplane Composition, and the offline test harness. NOT
  for writing app/workload manifests that must PASS Kyverno — that is the consumer
  side, use `authoring-k8s-workloads`. NOT for the per-environment restrict-images /
  restrict-route-hostnames policies — those are owned by the Crossplane Composition
  (`crossplane-composition-authoring`).
---

# Authoring Kyverno ClusterPolicies (the `policy` module)

This is the **producer** side of policy — writing the guardrails. The consumer side
(writing workloads that pass them) is `authoring-k8s-workloads`. Kyverno is **3.8.1**,
in **Enforce** on both preprod and platform (ADR-014). The authoritative per-cluster
catalog is `docs/architecture/kyverno-policy-catalog.md`; break-glass and the
Audit→Enforce flip live in `docs/runbooks/kyverno-break-glass.md`.

Module root: `infra/modules/policy/`. The policies ship as a **local bundled Helm
chart**, `infra/modules/policy/policies-chart/`:

- `templates/*.yaml` — one file per concern; a file may hold several ClusterPolicies
  (e.g. `pod-hardening.yaml` bundles four Pod policies at different tiers,
  `rbac-hardening.yaml` holds the two RBAC denies).
- `templates/_helpers.tpl` — the shared helpers (use these, don't re-roll matchers):
  `kpp.labels`, `kpp.environmentNamespaceSelector`, `kpp.excludeInfra`,
  `kpp.registryPatterns`, `kpp.skipPlatformPrincipals`.
- `values.yaml` — **every dynamic knob lives here**, never hardcoded in a template
  (validationFailureAction, failurePolicy, complianceTier, allowedRegistries,
  excludeNamespaces, verifySubjectsProduct, the trusted-CI subject regexes, …).

Two Helm releases (`main.tf`): the **engine** first, the **policies chart** second
with `depends_on` — avoids the webhook chicken-and-egg. Don't merge them.

## House conventions for a ClusterPolicy

- **Name**: `<verb>-<target>`, lowercase, dashes, **stable across versions**
  (`restrict-wildcard-rbac`, `disallow-default-namespace`, `block-public-loadbalancer`).
  Per-product policies are generated as `verify-images-product-<team>-<product>`.
- **Labels**: `{{- include "kpp.labels" . | nindent 4 }}`.
- **Annotations**: `policies.kyverno.io/{title,category,severity,subject,description}`.
- **`spec.background`**: `true` for background-scannable rules; **`false`** for any rule
  that reads `request.userInfo` (RBAC / default-namespace / principal-aware) — Kyverno
  forbids userInfo in background scans, and a `true` there silently won't evaluate.
- **`spec.failurePolicy: {{ .Values.failurePolicy }}`** and per-rule
  `validationFailureAction: {{ .Values.validationFailureAction }}` — never hardcode
  Audit/Enforce; it's driven per-cluster from the unit.
- **Mutate policies always fail-open** (`failurePolicy: Ignore`) — a best-effort default
  must never block admission. Only validate/verify rules fail-closed.
- **Scoping** — pick the helper, don't write raw selectors:
  - environment-namespace-targeted → `include "kpp.environmentNamespaceSelector"`
  - cluster-wide but skip platform principals → `include "kpp.skipPlatformPrincipals"`
    (deployer, ArgoCD, system controllers) as a precondition
  - never hit infra namespaces → `include "kpp.excludeInfra"` in the exclude block
- **Gates**: wrap optional policies in value gates (`{{- if .Values.enableImageVerification }}`)
  and tier gates (`{{- if ne .Values.complianceTier "standard" }}` for hipaa/pci-only
  rules like `require-ro-rootfs`, `require-pod-security-restricted`).

## Per-product supply-chain policies (the ADR-046 split)

**Platform owns** the trust-root verification — `verify-images-product-<team>-<product>`
and `verify-attestations-product-<team>-<product>` (cosign keyless against the shared
`trusted-ci/build-sign.yml` signer, ADR-050 + SLSA L3, ADR-042). **The Crossplane
Composition owns** the per-*environment* `restrict-images-*` and
`restrict-route-hostnames-*` — do **not** add those here (see
`crossplane-composition-authoring`).

These render by looping a map derived from the **Product registry** at the unit, not in
the module. The unit (`infra/live/aws/{preprod,platform}/.../policy/terragrunt.hcl`)
does `fileset`+`yamldecode` over `gitops/products/<team>/<product>.yaml` to build
`verify_subjects_product` (`{team, product, repo, registryPrefix}`), and the template
loops `{{- range $key, $p := .Values.verifySubjectsProduct }}`. Isolation is **per-cert
extension, not per-subject** — the shared signer subject is identical for all products,
so the policy gates on `additionalExtensions.githubWorkflowRepository: {{ $p.repo }}`,
which Fulcio sets from the caller repo's OIDC and another product cannot forge.

## Test offline before you apply

```bash
infra/modules/policy/.kyverno-tests/run.sh
```

Renders the chart with `helm template`, runs `kyverno test` against fixtures, plus a
mutation smoke-check and a per-product render check. Cluster-free; mirrors CI. The
Kyverno CLI must match the chart appVersion (1.18.x).

## Apply: Audit first, then Enforce, then promote

Never flip straight to Enforce. The pattern (per `kyverno-break-glass.md`):

1. Edit/add the template + any `values.yaml` knob; run the test harness.
2. Apply to **preprod** with `validation_failure_action = "Audit"`, `terragrunt apply`.
3. Watch PolicyReports against real workloads: `kubectl get policyreport -A`.
4. When clean, flip the unit's `validation_failure_action = "Enforce"` (one-line) and
   `terragrunt apply`; verify `kubectl get clusterpolicy <name> -o yaml`.
5. Promote the same change to the **platform** unit.

> EKS is private-only (ADR-010) — reach the API over Tailscale (`cluster-access`),
> never the public endpoint. Manual `terragrunt apply` assumes `PlatformDeployer`.

## Minimal example — add a validate ClusterPolicy

`policies-chart/templates/require-team-label-annotation.yaml`:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-cost-center-annotation
  labels:
    {{- include "kpp.labels" . | nindent 4 }}
  annotations:
    policies.kyverno.io/title: Require cost-center annotation
    policies.kyverno.io/category: Best Practices
    policies.kyverno.io/severity: low
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Environment pods must carry a cost-center annotation for chargeback.
spec:
  background: true
  failurePolicy: {{ .Values.failurePolicy }}
  rules:
    - name: require-cost-center
      match:
        any:
          - resources:
              kinds: [Pod]
              {{- include "kpp.environmentNamespaceSelector" . | nindent 14 }}
      validate:
        failureAction: {{ .Values.validationFailureAction }}
        message: "Pods require the platform.refplat.org/cost-center annotation."
        pattern:
          metadata:
            annotations:
              platform.refplat.org/cost-center: "?*"
```

Add a pass/fail case to `.kyverno-tests/`, run `run.sh`, then Audit→Enforce→promote.

## Gotchas

- **Webhook ports**: on `webhook_host_network=true`, admission is on **9445** / cleanup
  **9444** (Crossplane's provider-kubernetes squats :9443). The chart's probe ports must
  be overridden to match the server port, and `controllerRuntimeMetrics.bindAddress`
  disabled — otherwise CrashLoopBackOff on restart. See `main.tf` comments.
- **`validationFailureAction` (per-policy: Audit/Enforce)** is distinct from
  **`failurePolicy` (webhook config: Ignore/Fail)** — the latter is derived from the
  former in `main.tf`. In Enforce, `failurePolicy: Fail` blocks pod creation if the
  webhook is slow — that's the break-glass scenario.
- **Mutate strategic-merge**: keep securityContext + automountServiceAccountToken in one
  patch so Kyverno autogen resolves the type correctly; two patches can fail autogen.
- **ECR read** for image verification is scoped to `repository/team-*` only.
- **PSA baseline is the floor, Kyverno layers above it** (ADR-027) — they're
  complementary, not redundant; don't reimplement baseline PSS as a ClusterPolicy.

## References

- `docs/architecture/kyverno-policy-catalog.md` — authoritative per-cluster catalog + status
- `docs/runbooks/kyverno-break-glass.md` — emergency disable + Audit↔Enforce flip
- `infra/modules/policy/README.md`, `infra/modules/policy/policies-chart/`
- ADRs: 014 (Kyverno), 027 (PSA+Kyverno layering), 041 (Pod Identity backstop),
  042 (SLSA L3), 046 (supply-chain split), 050 (shared signer), 067 (domain model)
