# Compliance Framework

## Overview

The Reference Platform implements a compliance framework that addresses various regulatory requirements and industry standards. This document outlines the compliance controls, implementation patterns, and validation mechanisms used in the platform. The control-level mapping of Service Control Policies to SOC2/HIPAA/PCI/ISO/NIST/CIS lives in [SCP control mapping](../../docs/compliance/scp-control-mapping.md).

## Compliance Standards

The platform is designed to support the following compliance standards:

1. **SOC 2**: For service organization controls
2. **ISO 27001**: For information security management
3. **GDPR**: For data protection in the European Union
4. **HIPAA**: For healthcare information (where applicable)
5. **PCI-DSS**: For payment card industry data security (where applicable)

## Three-Tier Compliance Model

The platform implements a tiered compliance model driven by the `compliance_tier` value in each workload's `workload.hcl`. Each tier inherits all controls from the tier below it.

### Tier 1: Standard (SOC2)

Applies to the current `platform` and environment workloads (all `standard` today).

| Control Area | Implementation |
|-------------|----------------|
| Compute isolation | Shared EKS cluster with **namespace isolation** (vCluster deferred, ADR-033) — namespace, ResourceQuota, LimitRange per team |
| Network | Private VPC subnets; default-deny Cilium NetworkPolicies; security groups; private EKS API |
| Identity | IAM Identity Center (SSO); purpose-built IAM roles; IRSA / EKS Pod Identity (no static keys) |
| Encryption | KMS (EKS secrets, CloudTrail) + SSE-S3 (AES256); TLS 1.2+ in transit; EBS encrypted by SCP |
| Endpoints | Private-only EKS API; SSM bastion; Tailscale VPN |
| Logging | CloudTrail (per-account, 90-day) + VPC Flow Logs + observability (Prometheus/mimir) |
| Policy | Kyverno Enforce (image provenance + cosign verify, pod security, resource limits, RBAC hardening) above PSA baseline |

### Tier 2: HIPAA

Applies to: `hipaa` workload. Inherits all Standard controls, plus:

| Control Area | Implementation |
|-------------|----------------|
| Compute isolation | Dedicated EKS cluster (no shared tenancy) |
| Network | Isolated VPC (no default hub peering); private EKS API endpoint |
| Encryption | Customer-managed keys (CMK) for all data at rest; host encryption on all nodes |
| Logging | 365-day log retention; immutable audit trail |
| Access | JIT access for operations; break-glass procedures documented |
| Data handling | PHI labeling enforced via Kyverno; no PHI in non-HIPAA workloads |

### Tier 3: PCI

Applies to: `pci` workload. Inherits all HIPAA controls, plus:

| Control Area | Implementation |
|-------------|----------------|
| Network | CDE-segmented VPC; deny-all default network policy; WAF on all ingress |
| Monitoring | IDS/IPS enabled; real-time alerting on policy violations |
| Access | MFA for all CDE access; quarterly access reviews |
| Segmentation | Annual penetration test of segmentation controls |
| Policy | Kyverno strict policies: mandatory network policies per namespace, deny privileged escalation |

## Control Implementation

### Technical Controls

- **Access control**: IAM (Identity Center + purpose-built roles), Kubernetes RBAC, and namespace-scoped RoleBindings; IRSA / Pod Identity
- **Encryption**: SSE with platform-managed or customer-managed keys depending on tier; TLS everywhere
- **Logging and monitoring**: Centralized CloudTrail + CloudWatch; Prometheus/mimir/Grafana stack; retention scaled by tier
- **Network security**: security groups, private endpoints, Cilium NetworkPolicies; segmentation validated per tier
- **Secure configuration**: Kyverno admission policies; AWS SCP guardrails; CIS benchmark scanning

### Administrative Controls

- Policy management
- Risk assessment
- Training and awareness
- Incident response
- Vendor management

## Compliance Validation

Compliance is validated through:

1. **Kyverno audit reports** -- policy violations are surfaced as Kubernetes events and PolicyReports
2. **Terraform plan review** -- compliance-relevant changes (encryption, network rules, RBAC) are flagged in PR checks
3. **Periodic scanning** -- CIS benchmarks and cloud security posture management tools run on a schedule
4. **State drift detection** -- Terragrunt detects configuration drift and alerts on non-compliant resources

## Implementation in Terraform

Compliance controls are encoded in Terraform modules and enforced via the workload hierarchy:

- The `compliance_tier` variable propagates from `workload.hcl` through `_base.hcl` into every module
- Modules use `compliance_tier` to conditionally enable controls (e.g., CMK encryption, private cluster, log retention)
- Golden-path modules provide pre-configured, compliant defaults for each tier
- Self-service workload creation uses `workload.hcl` templates that set the appropriate tier and inherit all required controls

## Next Steps

Continue to [Tagging Strategy](12-tagging-strategy.md) to understand how resource tagging is used in the Reference Platform.
