# ADR-014: Kyverno as Policy Engine

**Date:** 2026-05-23

**Status:** Accepted — **Deployed (Phase 1, 2026-05-29)**. Kyverno is installed via the `policy`
module (`infra/modules/policy/`) and the live `policy` units on preprod and platform. Pod Security
Admission (`enforce=baseline` on tenant namespaces, ADR-027/ADR-039) remains the admission floor;
Kyverno layers above it. See **Deployment** and **Rollout & Roadmap** below.

> **Amendment (2026-06-03, #174 / [ADR-046](046-back-stack-for-developer-self-service.md)):** Tenant policy
> ownership is now **split**. The **per-tenant guardrails** — `restrict-images` (per-team ECR registry
> scoping) and `restrict-route-hostnames` (per-team Gateway hostname allow-list) — are provisioned **per team
> by the Crossplane Tenant Composition** (ADR-046), not by the `policy` unit's `tenant_registry_map`. The
> **platform-owned supply-chain verification** — `verify-images` (cosign keyless) and `verify-attestations`
> (SLSA, ADR-042) — stays in the `policy` module/unit and is deployed for **all** teams, including
> Crossplane-migrated ones, via the `migrated_teams` input. The engine, cluster-scoped policies, mutate
> defaults, and PSA floor are unchanged.

## Context

Kubernetes clusters need admission-time policy enforcement to prevent misconfigurations from being
deployed: containers running as root, images from untrusted registries, pods without resource
limits, namespaces without network policies. Without a policy engine, these guardrails exist only
in documentation and code review — they're not enforced at the cluster level.

The platform's compliance tier model (ADR-013) adds additional policy requirements: PCI workloads
need deny-all default network policies, HIPAA workloads need specific encryption configurations,
and all workloads need image provenance enforcement.

### Alternatives Considered

**1. OPA/Gatekeeper.** The most widely adopted Kubernetes policy engine. Uses Rego, a purpose-built
policy language, for writing constraints. Gatekeeper provides a Kubernetes-native CRD-based
interface on top of OPA. However, Rego has a steep learning curve — its datalog-inspired syntax is
unfamiliar to most infrastructure engineers. Writing and debugging Rego policies is significantly
slower than writing equivalent policies in a declarative format. The team's primary expertise is in
HCL and YAML, not logic programming.

**2. Kubewarden.** Uses WebAssembly (Wasm) modules for policy execution. Supports writing policies
in any language that compiles to Wasm (Rust, Go, etc.). Innovative approach but less mature
ecosystem, smaller community, and fewer pre-built policies than either OPA or Kyverno. Adding Wasm
compilation to the policy development workflow introduces unnecessary complexity.

**3. Kyverno (chosen).** Uses YAML-based policy definitions that match Kubernetes resource
structure. Policies are expressed as Kubernetes CRDs (`ClusterPolicy`, `Policy`) using familiar
patterns like `match`, `exclude`, `validate`, `mutate`, and `generate`. No new language to learn.
The policy format is immediately readable by anyone who understands Kubernetes manifests.

## Decision

Deploy Kyverno as the policy engine on all Kubernetes clusters via the shared `policy` module
(`infra/modules/policy/`).

### Deployment

Kyverno is deployed via Helm chart (version 3.8.1 / app v1.18.1, pinned in `_versions.hcl`). The
`policy` module installs **two Helm releases**: the engine (HA admission controller — `replica_count`
3 on platform, 1 on preprod) and a bundled local chart (`policies-chart/`) of the platform's
ClusterPolicies. A local chart needs no plan-time access to the Kyverno CRDs (which the engine
installs in the same apply), avoiding the `kubernetes_manifest` chicken-and-egg. The module is
cloud-agnostic and **holds no team-specific data** — per-tenant values (`tenant_registry_map`,
`allowed_registries`) are supplied by the Terragrunt unit from `teams.hcl`. The `compliance_tier`
variable gates restricted-grade pod policies (rendered only for `hipaa`/`pci`).

Tenant-targeted policies match the `platform.refplat.org/tenant` namespace label; infra namespaces
are excluded. Cluster-scoped policies (RBAC bindings, default-namespace) skip platform controllers
via an `exclude_principals` allow-list so addon reconciliation is never blocked.

### Rollout & Roadmap

**Audit-first.** Each phase deploys with `validation_failure_action = "Audit"` (records PolicyReports,
webhook fail-open `Ignore`) on preprod first; once PolicyReports are confirmed clean against real
workloads it flips to `"Enforce"` (rejects at admission, webhook fail-closed `Fail`), then promotes to
platform. The flip is a one-line input change. This realizes the risk mitigation noted below
(test before enforce; break-glass via webhook `failurePolicy` — see `docs/runbooks/kyverno-break-glass.md`).

**Phases** (each its own PR; tracked as GitHub issues):

1. **Engine + core admission `validate`** *(this ADR — done)*: registry/per-team image scoping,
   cross-team IRSA-annotation guard, RBAC hardening, resource/label/probe requirements, no public
   LB/NodePort, no `default` namespace, tenant namespace naming, tier-gated restricted PSS + RO-rootfs.
2. **`mutate`** *(done)*: auto-inject safe defaults on tenant workloads — hardened securityContext
   (safe subset), `automountServiceAccountToken: false`, `team`/`app.kubernetes.io/name` labels —
   backed by `disallow-privilege-escalation`/`require-seccomp` validate guards and ArgoCD
   `ignoreDifferences`. `generate`-based namespace governance is split out to the multi-namespace /
   self-service tenant-model design (issue #88).
3. **Supply chain** *(done — Enforce on preprod)*: `cosign` **keyless** signing (GitHub OIDC →
   Fulcio/Rekor) in app CI (`app-alpha`) + per-team `verifyImages` policies that admit only images signed
   by that team's own workflow identity, **plus** `verifyAttestations` requiring a CycloneDX SBOM and a
   SLSA Build L3 provenance from the isolated `trusted-ci` signer
   ([ADR-042](042-isolated-build-provenance-slsa-l3.md)). Kyverno gains **IRSA** (ECR read) to fetch
   signatures; verification rolls Audit→Enforce via its own `verify_failure_action`, independent of the
   other policies. Full picture:
   [`supply-chain-overview.md`](../architecture/supply-chain-overview.md) /
   [`cosign-image-signing.md`](../architecture/cosign-image-signing.md).
4. **Shift-left CLI** *(done)*: a reusable composite action (`.github/actions/kyverno-validate`) renders
   the tenant policies (`mutate` on, `verifyImages`/`cleanup` off) and runs `kyverno apply` against an
   app's manifests in **PR CI**, failing before merge — same checks as admission, earlier. Dogfooded in
   platform CI against committed compliant/broken sample apps. App repos opt in via a `validate.yml`
   calling `uses: asanexample/platform/.github/actions/kyverno-validate@main`. Feedback gate only —
   admission stays the enforcement point. See [`cosign-image-signing.md`'s sibling
   doc](../architecture/kyverno-shift-left.md).
5. **Ingress guard + cleanup** *(done)*: per-team Gateway-API route **hostname guard** (anti-squatting
   on the shared wildcard listener — closes the ADR-029 gap) + a `CleanupPolicy` reaping finished
   CronJob Jobs. PolicyReport → Grafana **deferred** to the monitoring-stack effort (#93).

### Policy Categories

> The live, per-cluster list of enforced policies (preprod / platform / prod) is maintained in the
> **[Kyverno Policy Catalog](../architecture/kyverno-policy-catalog.md)**.

The following policy guardrails are enforced at admission time:

| Policy | Description | Tiers |
|--------|-------------|-------|
| Image provenance | Only images from approved registries (per-team ECR scoping) | All |
| Pod security | Restricted pod security standards (no privileged, no host networking) | All |
| Resource limits | All pods must declare resource requests and limits | All |
| Label requirements | Workload and compliance-tier labels required on namespaces | All |
| Network policy enforcement | Every namespace must have a default-deny network policy | PCI (required), all (recommended) |

### Integration with Compliance Tiers

The `compliance_tier` variable drives policy strictness:

```hcl
variable "compliance_tier" {
  description = "Compliance tier to enforce (standard, hipaa, pci)"
  type        = string
  default     = "standard"
  validation {
    condition = contains(["standard", "hipaa", "pci"], var.compliance_tier)
  }
}
```

Standard tier enforces baseline policies. HIPAA and PCI tiers add stricter policies on top. The
module supports `additional_policies` as a map of raw YAML manifests for custom policy injection
beyond the built-in set.

### Policy Mode

Each policy reaches **`Enforce`** (violations rejected at admission) as its steady state, but gets there
via the **audit-first rollout** above — deployed `Audit` (PolicyReports, webhook fail-open) on preprod,
confirmed clean against real workloads, then flipped to `Enforce` (webhook fail-closed) and promoted to
platform. Audit is the safe on-ramp, not the destination. Kyverno is currently in **Enforce** on both
preprod and platform.

## Consequences

**Positive:**

- YAML-based policies are readable and writable by the team without learning a new language
- Policies are version-controlled as Kubernetes CRDs alongside infrastructure code
- Admission-time enforcement prevents misconfigurations from reaching the cluster, rather than
  detecting them after deployment
- Compliance tier integration means regulated workloads get stricter policies automatically
- Built-in mutation and generation capabilities enable auto-adding labels, default network policies,
  and resource quotas

**Negative:**

- Kyverno runs as a webhook in the admission path — if Kyverno is down or slow, it can block
  all pod creation. Mitigated by Kyverno's high-availability mode (multiple replicas) and
  failure policy configuration.
- YAML-based policies, while readable, are less expressive than Rego for complex logic (e.g.,
  cross-resource validation, aggregation queries). If policy requirements grow significantly in
  complexity, Kyverno may become a limitation.
- Policy development requires a running cluster for testing — there's no local REPL equivalent
  to OPA's `opa eval` command (though Kyverno CLI provides `kyverno test` for unit testing)

**Risks:**

- A misconfigured Kyverno policy could block legitimate deployments. Mitigated by testing policies
  in the platform environment before promoting to production, and by maintaining a break-glass
  process to disable Kyverno in emergencies.
- Kyverno's webhook has a timeout (default 10 seconds). Complex policies that exceed this timeout
  cause admission failures. Mitigated by keeping policies simple and focused.
