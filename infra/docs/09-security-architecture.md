# Security Architecture

## Overview

The Reference Platform enforces **defense in depth** across the AWS infrastructure —
from the AWS Organization down to individual pods. This document describes the security
principles and the concrete AWS controls that implement them. (The platform is AWS-first;
the same patterns would map to Azure/GCP equivalents when those clouds land — there is no
Azure/GCP deployment today.)

## Security Principles

1. **Defense in Depth** — multiple independent control layers (org SCPs → IAM → network →
   admission → runtime).
2. **Least Privilege** — purpose-built roles; humans operate but do not author (ADR-040).
3. **Secure by Default** — private endpoints, default-deny NetworkPolicies, encryption on.
4. **Identity-Based** — no long-lived credentials; federated identity everywhere.
5. **Encryption Everywhere** — at rest (KMS/AES256) and in transit (TLS).
6. **Continuous Validation** — admission policy (Kyverno), runtime detection (Falco), audit (CloudTrail).

## Identity and Access Management

- **AWS Organizations + SCPs** (ADR-003) — org-wide guardrails: no leaving the org, root
  lockdown, mandatory encryption (EBS/S3/RDS), IMDSv2, region restriction, no IAM users,
  protected audit services, `Team`-tag integrity. Exempt only for `OrganizationAccountAccessRole`,
  `PlatformDeployer`, `github-actions-terratest`.
- **IAM Identity Center (SSO)** — all human access is federated (no IAM users; the
  `restrict-iam-users` SCP blocks `iam:CreateUser`/`CreateAccessKey`). Permission sets map to
  groups (Admins, Developers, ReadOnly; per-team `Dev-<team>`).
- **Purpose-built IAM roles** (ADR-007/039/040):
  - `PlatformAdmin` (platform, preprod) — kubectl **operate/observe, not author**; AWS `ReadOnlyAccess`
    plus a deny on secret/data exfil, and SSM-to-bastion only.
  - `PlatformDeployer` (platform, preprod, test) — the Terragrunt/IaC apply role.
  - `DeveloperAccess-<team>` (preprod) — per-team, namespace-scoped kubectl via group-mapped EKS
    access entries + a `environment-developer` RoleBinding.
  - `OrganizationAccountAccessRole` — break-glass only.
- **Pod-level AWS identity**: **IRSA** for platform add-ons (ADR-018), **EKS Pod Identity** for
  environment workloads (ADR-041) — short-lived STS credentials, no static keys, no cross-team annotation
  (Kyverno backstops `disallow-irsa-annotation-cross-team`).
- **GitHub Actions OIDC** (ADR-036) — keyless CI; per-team `github-actions-ecr-push-<team>` roles
  scoped to that team's ECR repos.

## Network Security

- **Private EKS API endpoints** (ADR-010) — both clusters are private-only; access via **Tailscale**
  subnet routers (ADR-011) or the **SSM bastion** (ADR-020). No SSH, no public API.
- **Cilium NetworkPolicies** (ADR-008) — eBPF-enforced. Environment namespaces are **default-deny ingress**
  with explicit allows for the Gateway (`fromEntities: [ingress]`), DNS, and the Pod Identity agent;
  egress to IMDS is blocked (node enforces IMDSv2 hop-limit=1).
- **Gateway API ingress** (ADR-017/029) — Cilium Gateway with TLS (Let's Encrypt DNS-01). Platform uses
  an **internal** NLB (Tailscale-only); preprod uses a **public** NLB. `LoadBalancer`/`NodePort` Services
  are denied by Kyverno (Gateway-only ingress).
- **VPC isolation** — non-overlapping per-env /16 CIDRs (ADR-015); cross-account connectivity only via
  **Transit Gateway** (ADR-034) with security-group scoping; VPC Flow Logs to CloudWatch.

## Data Protection

- **Encryption at rest** — EKS secrets via **KMS** envelope encryption; CloudTrail S3 via KMS; environment/
  mimir S3 via SSE-S3 (AES256); EBS encrypted by default (SCP-enforced).
- **Encryption in transit** — TLS everywhere (Gateway termination, Hubble TLS, service-to-service).
- **Secrets** (ADR-019/024/025/026) — AWS Secrets Manager as the source of truth; **External Secrets
  Operator** (IRSA) syncs to Kubernetes; per-account isolation (no cross-account reads by default);
  hierarchical naming; `PlatformAdmin` is **denied** `secretsmanager:GetSecretValue` (break-glass only).

## Supply-Chain Security

- **Image signing** (ADR-014 Phase 3) — app CI **cosign-signs** images keyless (GitHub OIDC →
  Fulcio/Rekor); Kyverno `verify-images-<team>-<product>` admits only images signed by that product's workflow.
- **SBOM + provenance** — CycloneDX SBOM + **SLSA Build L3** provenance (isolated `trusted-ci` signer,
  ADR-042), required at admission by `verify-attestations-<team>-<product>` (Enforce on preprod).
- **Per-product ECR scoping** (ADR-028) — `team-<team>/<product>-*` repos, immutable tags, scan-on-push.

## Detection & Monitoring

- **CloudTrail** (ADR-037) — per-account audit trail (log-file validation, KMS, CloudWatch); metric
  filter/alarm on Secrets Manager activity.
- **Falco** (ADR-045) — runtime threat detection (modern eBPF) on preprod.
- **GuardDuty / Config / Security Hub / Access Analyzer** — protected from tampering by the
  `protect-security-services` SCP.
- **Observability** (ADR-043/044) — Prometheus + Grafana + durable mimir + SNS alerting; **Hubble**
  for network flow visibility.

## Admission Policy (Kyverno)

[Kyverno](https://kyverno.io/) (ADR-014) runs in **Enforce** on preprod and platform, layered above the
Pod Security Admission `baseline` floor:

- **Image provenance** — approved-registry + per-product `team-<team>/<product>-*` scoping; cosign signature +
  attestation verification.
- **Pod hardening** — `mutate` injects `securityContext`/`automountServiceAccountToken: false`;
  backstops deny privilege-escalation and `seccompProfile: Unconfined`.
- **Multi-tenancy** — route-hostname allow-lists (anti-squatting, ADR-029), `LoadBalancer`/`NodePort`
  denial, no `default` namespace, cross-team IRSA-annotation guard, RBAC hardening (no `cluster-admin`,
  no wildcard verbs), required requests/limits + probes + labels.

Full per-cluster list: [Kyverno policy catalog](../../docs/architecture/kyverno-policy-catalog.md).

## Compliance Tier Enforcement

Security controls scale with the `compliance_tier` in each workload's `workload.hcl` (ADR-013):

### Standard (SOC2)

- Shared cluster with **namespace isolation** (vCluster deferred, ADR-033) — per-Environment
  (`<team>-<product>-<stage>`) namespace, ResourceQuota, LimitRange, default-deny NetworkPolicies,
  namespace-scoped RBAC.
- Private endpoints, audit logging, Kyverno Enforce.

### HIPAA

- **Dedicated cluster** (no shared tenancy), isolated VPC.
- Customer-managed KMS keys, host encryption, private API, 365-day log retention.
- Kyverno **restricted** PSS + read-only root filesystem + `runAsNonRoot` (tier-gated policies).

### PCI

- All HIPAA controls plus a CDE-segmented VPC, WAF on ingress, IDS/IPS, and a deny-all default
  network policy.

> HIPAA/PCI tiers are designed but **not yet deployed** — both live clusters are `standard`.

## Future Enhancements

- Shift-left scanning depth (Trivy/Semgrep already in CI; expand SCA/cost-of-ownership).
- Comprehensive SOC2/ISO 27001 control mapping (started — see
  [SCP control mapping](../../docs/compliance/scp-control-mapping.md)).
- Automated security validation gates in CI.

## Next Steps

Continue to [Compliance Framework](10-compliance-framework.md).
