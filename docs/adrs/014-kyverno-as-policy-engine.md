# ADR-014: Kyverno as Policy Engine

**Date:** 2026-05-23

**Status:** Accepted — **not yet deployed**. Pod Security Admission (`enforce=baseline` on tenant
namespaces, see ADR-027/ADR-039) is the current admission-control floor until Kyverno is deployed.

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

Kyverno is deployed via Helm chart (currently version 3.3.7, pinned in `_versions.hcl`). The
policy module accepts a `compliance_tier` variable that determines which policies are enforced.

### Policy Categories

The following policy guardrails are enforced at admission time:

| Policy | Description | Tiers |
|--------|-------------|-------|
| Image provenance | Only images from approved registries (ACR/ECR) | All |
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

Policies are deployed in `Enforce` mode by default — violations are rejected at admission. This
is a deliberate choice over `Audit` mode, which logs violations but allows them through. Audit
mode is useful for policy rollout but provides no actual protection.

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
