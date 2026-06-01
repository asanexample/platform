# ADR-013: Compliance Tier Model

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform hosts workloads with varying regulatory requirements. Some tenants handle protected
health information (PHI) subject to HIPAA, others process payment card data subject to PCI DSS,
and many have no specific regulatory requirements beyond standard SOC 2 controls.

These different compliance regimes impose fundamentally different infrastructure requirements:

1. **Isolation model.** HIPAA and PCI require dedicated compute and network resources — shared
   Kubernetes clusters with namespace-based isolation are insufficient. Standard workloads can
   share infrastructure safely.

2. **Encryption requirements.** HIPAA mandates encryption at rest with specific key management.
   PCI adds requirements around key rotation and access logging.

3. **Network controls.** PCI requires explicit network segmentation (CDE boundaries) and deny-all
   default network policies. Standard workloads need network policies but can use allow-by-default
   with specific deny rules.

4. **Retention and auditing.** HIPAA requires 6-year record retention. PCI requires 1-year audit
   log retention. Standard workloads follow the organization's default retention policy.

Building every workload to the highest compliance tier wastes resources and adds unnecessary
operational complexity. Building everything to the lowest tier fails to meet regulatory obligations.

### Alternatives Considered

**1. Single tier — build everything to PCI standard.** Every workload gets a dedicated cluster,
CMK encryption, deny-all network policies, and maximum log retention. This simplifies the model
(no decisions to make) but is prohibitively expensive — dedicated EKS clusters cost ~$73/month
for the control plane alone, plus node costs, and most workloads don't need this isolation.

**2. Ad-hoc per-workload configuration.** Let each workload team decide its own security controls
based on its compliance requirements. No standardized tiers — just documentation and guidelines.
This provides maximum flexibility but no guardrails, making it easy to under-provision controls
for regulated workloads and impossible to audit compliance posture systematically.

**3. Tiered compliance model (chosen).** Define three explicit tiers — Standard (SOC 2), HIPAA,
and PCI — each with a prescriptive set of infrastructure controls. The tier is declared in the
workload's `workload.hcl` and flows through the configuration hierarchy to drive module behavior.

## Decision

Implement a three-tier compliance model declared per workload via `compliance_tier` in
`workload.hcl`. Each tier prescribes specific infrastructure controls:

### Tier Definitions

| Control | Standard (SOC 2) | HIPAA | PCI |
|---------|-------------------|-------|-----|
| **Compute isolation** | Shared cluster, namespace isolation (vCluster deferred — ADR-033) | Dedicated cluster | Dedicated cluster |
| **Network isolation** | Shared VPC, TGW-connected | Isolated VPC, no TGW peering | CDE-segmented VPC |
| **Encryption at rest** | Platform-managed keys | Customer-managed keys (CMK) | CMK + rotation policy |
| **Host encryption** | Not required | Required | Required |
| **API server access** | Private endpoint | Private endpoint | Private endpoint |
| **Network policy default** | Allow (explicit deny) | Allow (explicit deny) | Deny-all (explicit allow) |
| **WAF** | Optional | Recommended | Required on all ingress |
| **IDS/IPS** | Not required | Not required | Required |
| **Log retention** | 30 days | 365 days | 365 days |

### Configuration Declaration

Each workload directory contains a `workload.hcl` that declares the compliance tier:

```hcl
locals {
  workload        = "platform"
  compliance_tier = "standard"
  workload_tags = {
    Workload       = "platform"
    ComplianceTier = "standard"
  }
}
```

The `compliance_tier` is validated by the policy module (Kyverno) with
`contains(["standard", "hipaa", "pci"], var.compliance_tier)`.

**Tier → policy mapping (Kyverno, ADR-014).** All tiers get the Phase 1 baseline pack (per-team image
registry scoping, cross-team IRSA guard, RBAC hardening, `require-requests-limits`,
`require-workload-labels`, `require-pod-probes`, `disallow-latest-tag`, `block-public-loadbalancer`,
`disallow-default-namespace`). The `hipaa`/`pci` tiers additionally render
`require-pod-security-restricted` (full Restricted PSS) and `require-ro-rootfs` (read-only root
filesystem). HIPAA/PCI-specific packs beyond these are tracked for when those tiers are deployed.

### Standard-Tier Isolation (Namespace; vCluster Deferred)

Standard-tier workloads share physical clusters. Today, tenant isolation is **namespace-based** — a
dedicated namespace per team with default-deny NetworkPolicies, resource quotas/limits, per-team RBAC,
and per-team AWS access via Pod Identity (see [ADR-027](027-hybrid-tenant-isolation-model.md),
[ADR-031](031-multi-app-tenant-model.md), [ADR-041](041-pod-identity-for-tenant-workloads.md)).

**vCluster** — a virtual cluster per tenant with its own API server and control plane — was the original
design for stronger standard-tier isolation, but is **deferred**
([ADR-033](033-defer-vcluster-tenant-support.md)): the OSS chart can't sync HTTPRoute and other CRDs to
the host cluster. It remains the intended upgrade once that's resolved.

HIPAA and PCI workloads bypass shared isolation entirely and run on dedicated physical clusters.

### Tag Propagation

The `ComplianceTier` tag is added to `workload_tags` and merged into the tag hierarchy by
`_base.hcl`. This tag appears on all resources created within the workload, enabling compliance
auditing by tag queries across the cloud estate.

## Consequences

**Positive:**

- Clear, auditable compliance posture — every workload has an explicit tier declaration
- Proportional cost — standard workloads share infrastructure; only regulated workloads pay for
  dedicated resources
- Prescriptive controls — teams don't need to figure out what "HIPAA-compliant infrastructure"
  means; the tier definition prescribes it
- Tag-based auditing — `ComplianceTier` tag on all resources enables automated compliance checks
- Namespace isolation gives standard-tier tenants separation without dedicated-cluster overhead
  (vCluster is the deferred stronger-isolation upgrade — ADR-033)

**Negative:**

- Three tiers may not cover all regulatory scenarios (e.g., FedRAMP, SOX). Additional tiers would
  need to be defined and implemented.
- The tier boundary is per-workload, not per-namespace or per-application. A single regulated
  application in a workload forces the entire workload to the higher tier.
- Namespace isolation is weaker than per-tenant control-plane isolation; vCluster would close that gap
  but adds its own operational complexity (a reason it's currently deferred — ADR-033)
- Dedicated clusters for HIPAA/PCI multiply infrastructure cost and operational surface area

**Risks:**

- If a workload is miscategorized (e.g., handling PHI but declared as `standard`), it runs on
  shared infrastructure without HIPAA controls. Mitigated by making `compliance_tier` a required
  field in `workload.hcl` and reviewing tier assignments during workload onboarding.
- Namespace isolation shares one control plane across tenants, so a control-plane or CNI vulnerability
  could theoretically cross namespace boundaries — weaker than physical/vCluster isolation. Mitigated by
  Kyverno admission hardening, default-deny NetworkPolicies, and keeping regulated data off shared
  clusters.
