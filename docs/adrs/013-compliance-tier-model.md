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
| **Compute isolation** | Shared cluster (vCluster) | Dedicated cluster | Dedicated cluster |
| **Network isolation** | Shared VNet, hub-peered spoke | Isolated VNet, no hub peering | CDE-segmented VNet |
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

### vCluster for Standard Tier

Standard-tier workloads share physical clusters. Tenant isolation is provided by vCluster, which
gives each tenant a virtual Kubernetes cluster with its own API server, control plane, and resource
namespace. vClusters are CNCF-certified and provide:

- API server isolation (separate authentication and authorization)
- Resource quotas and limit ranges per virtual cluster
- Network policy isolation between virtual clusters
- Independent CRD management

HIPAA and PCI workloads bypass vCluster entirely and run on dedicated physical clusters.

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
- vCluster provides strong isolation for standard-tier tenants without dedicated cluster overhead

**Negative:**

- Three tiers may not cover all regulatory scenarios (e.g., FedRAMP, SOX). Additional tiers would
  need to be defined and implemented.
- The tier boundary is per-workload, not per-namespace or per-application. A single regulated
  application in a workload forces the entire workload to the higher tier.
- vCluster adds operational complexity — virtual clusters must be managed, monitored, and upgraded
  alongside the host cluster
- Dedicated clusters for HIPAA/PCI multiply infrastructure cost and operational surface area

**Risks:**

- If a workload is miscategorized (e.g., handling PHI but declared as `standard`), it runs on
  shared infrastructure without HIPAA controls. Mitigated by making `compliance_tier` a required
  field in `workload.hcl` and reviewing tier assignments during workload onboarding.
- vCluster isolation, while strong, is not identical to physical cluster isolation. A vulnerability
  in vCluster's syncer or the host cluster's control plane could theoretically cross tenant
  boundaries. Mitigated by keeping vCluster updated and restricting standard-tier workloads to
  non-regulated data.
