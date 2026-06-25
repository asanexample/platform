---
name: crossplane-composition-authoring
description: >-
  How to author and edit the Crossplane XEnvironment XRD + Composition in the
  `crossplane` module — the provisioner internals BEHIND the environment claim. Use
  when extending what an environment provisions (a new composed resource, a new
  spec/status field, a new provider service, per-service Pod Identity / IAM,
  self-service cloud resources), changing how the go-templating Composition renders,
  or validating Composition/XRD changes before applying. Covers the Pipeline-mode
  Composition, the EnvironmentConfig context, the status.domains state machine, the
  render/validate harness, the federated cross-account ECR wiring, and the CRITICAL
  safe-apply rule (in-place XRD edits can cascade-delete live XEnvironments). NOT for
  AUTHORING/DEBUGGING a specific environment claim (gitops/environments/**) — that is
  `environment-onboarding`. NOT for the platform-owned cosign verify policies
  (`kyverno-policy-authoring`).
---

# Authoring the XEnvironment XRD + Composition (`crossplane` module)

This is the **provisioner** side — the XRD and Composition that turn an `XEnvironment`
claim into namespace + quota + network policy + Pod Identity + ECR + per-product Kyverno
guardrails. *Using* the claim is `environment-onboarding`. The authoritative design doc
is `docs/architecture/crossplane-composition-authoring.md` (read it first); the API
contract is `docs/architecture/crossplane-environment-api.md`.

Module root: `infra/modules/crossplane/`. Key files:

- `charts/environment-api/templates/xenvironment-xrd.yaml` — the cluster-scoped XRD
  (CompositeResourceDefinition). Structural schema **only** — cross-object envelope
  checks are Kyverno, not schema (see below).
- `charts/environment-api/files/composition.yaml` — the Composition. Shipped raw via
  `.Files.Get` so Helm does **not** touch the inline `{{ }}` go-template delimiters.
- `charts/environment-policies/templates/` — the admission gates
  (`restrict-environment-envelope`, `restrict-environment-control-plane`).
- `.environment-api-tests/run.sh` (schema/CEL) and `render.sh` (Composition render).

## The pipeline

Pipeline-mode Composition, three steps:

1. `function-environment-configs` — merges the `platform-cluster-config`
   EnvironmentConfig (ecrRegistry, baseDomain, region, account IDs, clusterName,
   permissionsBoundaryArn, providerConfigEcr, …) into context.
2. `function-go-templating` — renders **all** composed resources from `$spec` + context.
3. `function-auto-ready` — marks the XR Ready.

Variables are bound up front (`$spec`, `$team`, `$product`, `$stage`, `$customer`, `$ns`
— truncated+hashed to 63 chars, `$tier`, `$suspended`, `$cfg`, `$ecrCfg`). `$suspended`
is true when `lifecycle.phase` is `suspended` or `decommissioning` and zeroes the
ResourceQuota (ADR-062 reversible suspend).

## What the Composition emits (per claim)

- **K8s** (via provider-kubernetes `Object`s): Namespace `<team>-<product>-<stage>`
  (per-customer: `<team>-<product>-<customer>-<stage>` — **customer is inserted before the
  stage**, not appended; the same ordering applies to the `Pod-…` IAM role name. Note the
  in-code comments and the XRD description mis-state this as a trailing suffix — the
  `printf` templating in `composition.yaml` is authoritative)
  (PSA labels), ResourceQuota (zeroed if suspended), LimitRange, default-deny +
  allow-gateway + allow-dns NetworkPolicies, CiliumNetworkPolicies (ingress entity +
  Pod-Identity egress), the `environment-developers` RoleBinding, per-`platformTrust`
  ClusterRoleBindings (ADR-081), and the per-product `restrict-images-<ns>` /
  `restrict-route-hostnames-<ns>` Kyverno policies.
- **AWS workload account** (provider-aws, ProviderConfig `default` = Pod Identity): per
  service an IAM role `Pod-<team>-<product>-…-<svc>` (truncated+hashed to 64) with the
  cluster permissions-boundary, an inline RolePolicy from the service's
  `permissions.aws.policyStatements` (deny-set-validated) + derived least-priv for any
  declared cloud resource (ADR-073), and the EKS PodIdentityAssociation.
- **AWS platform account** (ProviderConfig `platform-ecr` = assumeRoleChain): per service
  an ECR repo `team-<team>/<product>-<svc>`, `IMMUTABLE_WITH_EXCLUSION` (allows
  `sha256-*` cosign tags), scan-on-push, **`deletionPolicy: Orphan`** (product-scoped,
  shared across stages — images survive environment teardown).
- **Self-service cloud resources** (ADR-073 Phase A: S3/SQS/DynamoDB) with hardened
  defaults + a `<svc>-resources` ConfigMap of output names.

> **Not** emitted by the Composition: the platform-owned cosign
> `verify-images-product-*` / `verify-attestations-product-*` (those live in the `policy`
> module). And **#647**: the `DeveloperAccess-<team>` IAM role + EKS access entry are
> NOT yet emitted — only the in-cluster `<ns>:developers` RoleBinding is.

## The status.domains state machine (ADR-061)

The Composition writes the XR's own status to gate route admission. **Critical
go-template gotchas:**

- Emit the XEnvironment status document with **no**
  `gotemplating.fn.crossplane.io/composition-resource-name` annotation — with one,
  Crossplane treats it as a nested composed resource and never merges it into composite
  status (routes never go Active).
- Every *real* composed resource **must** have a unique
  `gotemplating.fn.crossplane.io/composition-resource-name` annotation.
- The current Composition computes `status.domains` from `$spec` only — it does **not**
  read observed resources (it binds `.observed.composite.resource`, never
  `.observed.resources`). *If* you ever need to read prior observed composed state, capture
  `{{- $observed := .observed.resources | default dict }}` once before any `range`, then
  `index $observed "<name>"` — but that pattern is not used here today.

The Kyverno `restrict-route-hostnames-<ns>` admits a route only while its host is
`state: Active` in `status.domains[]`.

## Validate offline before applying

```bash
infra/modules/crossplane/.environment-api-tests/run.sh      # schema + CEL validation
infra/modules/crossplane/.environment-api-tests/render.sh   # Composition render vs fixtures
infra/modules/crossplane/.kyverno-tests/run.sh              # envelope-policy behavior
```

Ad-hoc render: `crossplane render xr.yaml composition.yaml functions.yaml [--observed-resources <dir>]`.

## ⚠️ Safe-apply rule — XRD edits can cascade-delete

- **Composition changes are safe**: render-test, then `terragrunt apply` the crossplane
  unit. The `main.tf` chart-file checksum forces a Helm upgrade even on a template-only
  change; existing XRs reconcile the new Composition on the next refresh (~5 min).
- **XRD structural-schema changes / field removals can cascade-delete live
  XEnvironment objects.** The `tenant→environment` rename was deliberately deferred to a
  rebuild cutover for exactly this reason — do **not** apply a structural XRD change
  in-place to a cluster with live environments. Route schema changes through a cutover,
  or add fields additively with defaults.
- **Provider ordering**: `provider-kubernetes` must stay at list index 0 in `main.tf` so
  its webhook port stays stable.

Adding a provider service: add it to `var.provider_services`, append to
`local.aws_providers` (auto-indexed), extend the provisioner IAM policy if needed.

## Envelope checks are Kyverno, not schema

The XRD stays structural/self-contained. Cross-object rules — `spec.team ==
Product.team`, `tier ∈ Team.allowedTiers`, `stage ∈ Team.allowedStages`, quota caps,
residency ⊆ Team, `domains ⊆ Product.domains`, `platformTrust.clusterRoles ⊆ Team`, and
the IAM deny-set on `policyStatements` — are enforced by `restrict-environment-envelope`
at admission. `restrict-environment-control-plane` ensures only ArgoCD/break-glass can
create XEnvironments. Add cross-object validation there, not in the XRD.

## Minimal example — add an additive spec field

1. XRD (`xenvironment-xrd.yaml`), under `spec.properties` — additive, with a default:

   ```yaml
   labels:
     type: object
     additionalProperties: { type: string }
     default: {}
   ```

2. Composition (`composition.yaml`), in the Namespace Object's labels:

   ```yaml
   {{- range $k, $v := ($spec.labels | default dict) }}
   {{ $k }}: {{ $v | quote }}
   {{- end }}
   ```

3. `render.sh` (or `crossplane render`) to confirm the rendered namespace carries them;
   then `terragrunt apply` — existing XRs reconcile within ~5 min.

## References

- `docs/architecture/crossplane-composition-authoring.md` — the deep design doc
- `docs/architecture/crossplane-environment-api.md` — XRD/claim contract
- `docs/runbooks/environment-deprovisioning.md` — suspend vs hard-delete, ECR orphan
- ADRs: 041/047 (Pod Identity), 046 (supply-chain split), 048 (federated Crossplane),
  061 (ingress/status.domains), 062 (deprovisioning), 063 (Team git-native),
  067 (domain model), 073 (self-service cloud resources)
