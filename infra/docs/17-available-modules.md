# Available Modules

## Overview

The Reference Platform's infrastructure is decomposed into reusable OpenTofu modules.
The platform is **AWS-first today** — modules are either **AWS-specific**
(`infra/modules/aws/`) or **cloud-agnostic / shared** (`infra/modules/`, deployed via
Helm or the Kubernetes provider). There are **no `azure/` or `gcp/` modules yet**; the
shared modules are written cloud-agnostically so they can be reused when those clouds land.

Every resource-creating module implements the `create` toggle
(`variable "create" { type = bool, default = true }`) — setting `create = false`
disables all resource creation and returns safe null/empty outputs. **Each module has its
own `README.md`** with the full variable/output reference; this page is a navigable
catalog. Module source paths and Helm chart versions are pinned centrally in
`infra/live/aws/_versions.hcl`.

## AWS-Specific Modules (`infra/modules/aws/`)

| Module | Purpose |
|--------|---------|
| `organizations` | AWS Organizations: OUs, member accounts, Service Control Policies, Identity Center scaffolding (ADR-003/004/005) |
| `identity_center` | IAM Identity Center permission sets, groups, and account assignments |
| `state_bootstrap` | S3 bucket + DynamoDB lock table for the Terraform remote state backend (ADR-006) |
| `iam_roles` | Purpose-built IAM roles (PlatformAdmin, PlatformDeployer, per-team DeveloperAccess, per-service Pod-<team>-<product>-…-<svc>) (ADR-007/039/040/041) |
| `github_oidc` | GitHub Actions OIDC provider + per-team/role trust for keyless CI (ADR-036) |
| `networking` | VPC, multi-tier subnets, IGW, NAT, route tables, EKS networking, S3 gateway endpoint, flow logs (ADR-015) |
| `transit-gateway` | Hub-and-spoke Transit Gateway for cross-account VPC connectivity, shared via RAM (ADR-034) |
| `cross-vpc-dns` | Cross-VPC DNS for private EKS endpoints — dynamic-ENI PHZ or Resolver endpoints (ADR-035) |
| `route53` / `route53_delegation` | Route53 hosted zone(s) + NS delegation for per-environment DNS (ADR-022/030) |
| `eks` | EKS control plane (BYOCNI, private endpoint, OIDC provider, KMS secrets encryption) (ADR-009/010/018) |
| `eks-node-group` | EKS managed node groups (system/workload) with hardened launch templates (ADR-023) |
| `eks-addons` | EKS managed add-ons (coredns) + gp3 default StorageClass + EBS CSI IRSA (ADR-009) |
| `eks-pod-identity` | EKS Pod Identity associations for environment AWS access (ADR-041) |
| `karpenter` | Karpenter node autoscaling (NodePools/EC2NodeClasses, consolidation, BYOCNI startup-taint ordering) on both clusters (ADR-078) |
| `ecr` | Centralized, per-team ECR repositories with cross-account pull + immutable tags (ADR-028) |
| `s3` | Reusable private/encrypted S3 buckets (e.g. environment data, mimir blocks) |
| `ssm-bastion` | SSM Session Manager bastion (no SSH/inbound) for private cluster access (ADR-020) |
| `cloudtrail` | Per-account CloudTrail trail (S3, KMS, CloudWatch, secrets alarms) (ADR-037) |
| `sns-notifications` | SNS topic(s) for alerting (Alertmanager → email, Falco publisher) |
| `sops-kms` | Management `platform-sops` KMS key for SOPS-encrypted committed config secrets (ADR-066) |
| `cost-allocation-tags` | Activates AWS cost-allocation tags (Team/Product/Stage) for cost visibility |
| `cost-monitoring` | AWS Budgets + Cost Anomaly Detection → SNS → Slack (Chatbot) + email; platform bill-level cost alerting (ADR-092) |

## Cloud-Agnostic / Shared Modules (`infra/modules/`)

Deployed via Helm / the Kubernetes provider onto any cluster; reusable across clouds.

| Module | Purpose |
|--------|---------|
| `cilium` | Cilium CNI (BYOCNI, `kubeProxyReplacement`, Gateway API, Hubble) — datapath via `ipam_mode`/`routing_mode`; AWS runs overlay (cluster-pool + VXLAN), ENI optional/non-default (ADR-008) |
| `argo-rollouts` | Argo Rollouts controller + dashboard for progressive delivery (canary/blue-green, metric-gated analysis); dashboard fronted by `oauth2-proxy` (ADR-056) |
| `argocd` | ArgoCD GitOps engine + direct Keycloak OIDC SSO (Dex retired) + Pod Identity for ECR (ADR-021/053/059) |
| `argocd-apps` | Per-team AppProjects, Applications, and PR-preview ApplicationSets (ADR-031/032) |
| `argocd-clusters` | Registers spoke clusters (e.g. preprod) with the ArgoCD hub |
| `backstage` | Backstage developer portal (catalog, scaffolder, plugins) with direct Keycloak OIDC (ADR-051/064) |
| `cert-manager` | TLS via Let's Encrypt DNS-01 (Route53), ClusterIssuers |
| `external-dns` | Syncs Gateway/Service hostnames to Route53 |
| `external-secrets` | External Secrets Operator (Pod Identity → Secrets Manager / SSM) (ADR-019/047) |
| `secret-stores` | ClusterSecretStore (Secrets Manager + SSM backends) (ADR-024) |
| `keycloak` | Keycloak IdP-of-record deployment (the app-facing OIDC provider) (ADR-052/053/059) |
| `keycloak-config` | Keycloak realm/client/role configuration (OIDC clients for ArgoCD, Backstage, Grafana, …) (ADR-053) |
| `oauth2-proxy` | Reusable Keycloak-SSO front for UIs with no native auth (e.g. the Argo Rollouts dashboard) |
| `platform-directory` | Workforce identity directory + owner-resolution (maps commit/team → owning team for routing) (ADR-084) |
| `cloudnative-pg` | CloudNative-PG operator + PostgreSQL clusters (e.g. the Backstage database) |
| `gateway` | Foundational shared Cilium Gateway + ClusterIssuer (internal/public NLB), brought up early (ADR-029/060) |
| `gateway-config` | Cilium Gateway API: Gateway, HTTPRoutes, ClusterIssuer (internal/public NLB) (ADR-017/029) |
| `github-teams` | GitHub org-Team ownership of app repos, derived from the Team/Product registries (ADR-072) |
| `tailscale` / `tailscale-admin` | Tailscale subnet-router operator + tailnet ACL/OAuth management (ADR-011) |
| `actions-runner-controller` | Self-hosted GitHub Actions runners (ARC) on the platform cluster — in-VPC CI for cluster-facing applies; local/break-glass unit (ADR-065 / #323) |
| `policy` | Kyverno engine + bundled ClusterPolicies (validate/mutate + cosign verify) (ADR-014) — see below |
| `crossplane` | Crossplane v2 control plane — hub ECR provisioning + the per-cluster `XEnvironment` XRD/Composition, shipping the `crossplane-environment-api` + `environment-policies` charts (ADR-046/048/067) |
| `cluster-rbac` | `platform-operator` ClusterRole for the operate-not-author access model (ADR-040) |
| `observability` | kube-prometheus-stack hub: Prometheus + Grafana + Alertmanager (ADR-043) |
| `observability-*` (17 modules) | The LGTM+profiles stack: durable stores `-mimir`/`-loki`/`-tempo`/`-pyroscope` (ADR-044); collectors `-alloy`/`-beyla`/`-otel-collector`/`-otel-operator`/`-prometheus-agent`/`-pyroscope-ebpf`/`-events`; measurement `-slo`/`-blackbox`/`-k6`/`-opencost`/`-cloudwatch-exporter` (ADR-077) |
| `falco` | Runtime threat detection (modern eBPF) + falcosidekick (ADR-045) |
| `pagerduty` | Per-team on-call schedules + escalation policies in IaC, derived from team ownership (ADR-084) |
| `cloudflare/dns_delegation` | NS records in the Cloudflare parent zone delegating to Route53 (ADR-022) |
| `vcluster` | Virtual Kubernetes clusters — **deferred** (ADR-033) — see below |

## Policy Module (Kyverno) — detail

**Location**: `infra/modules/policy`

The Policy module installs the Kyverno policy engine (HA admission controller) via Helm and a bundled
local chart of the platform's admission-control ClusterPolicies. It layers above the Pod Security
Admission `baseline` floor (ADR-027/040) to express controls PSA cannot. The module holds **no
team-specific data** — per-cluster values are supplied by the Terragrunt unit, derived from the
`XEnvironment` registry (`gitops/environments/`) and the git-native `Product` CRs (ADR-067/069).

- Two Helm releases: the Kyverno engine + a local `policies-chart` (no `kubernetes_manifest`, so no
  plan-time CRD dependency)
- **Audit-first rollout**: `validation_failure_action` toggles `Audit` (record PolicyReports, webhook
  fail-open) ↔ `Enforce` (reject at admission, webhook fail-closed) in one input change
- Validate policies: per-product image-registry scoping, cross-team IRSA-annotation guard, RBAC hardening
  (`restrict-binding-clusteradmin`, `restrict-wildcard-rbac`), `require-requests-limits`,
  `require-workload-labels`, `disallow-latest-tag`, `block-public-loadbalancer`, `require-pod-probes`,
  `disallow-default-namespace`, route-hostname allow-lists; tier-gated restricted PSS + read-only rootfs
- `mutate` defaults (securityContext, automount, labels) and **cosign image + attestation verification**
  (`verify-images`, `verify-attestations` — Enforce; ADR-014/042) with their own failure-action knobs
- Compliance tier selection (`standard`, `hipaa`, `pci`)
- `additional_policies` escape hatch for raw ClusterPolicy YAML; `create` toggle
- Cluster-free unit tests via the Kyverno CLI (`.kyverno-tests/run.sh`) — also dogfooded in CI

**Key Variables**: `validation_failure_action`, `verify_failure_action`,
`verify_attestations_failure_action`, `compliance_tier`, `allowed_registries`, `tenant_registry_map`,
`verify_subjects`, `verify_subjects_product`, `attest_caller_repos`, `replica_count`, `helm_chart_version`,
`additional_policies`, `tags`. Full reference: the module's `README.md` and the
[Kyverno policy catalog](../../docs/architecture/kyverno-policy-catalog.md).

## vCluster Module — detail (deferred)

**Location**: `infra/modules/vcluster`

Deploys virtual Kubernetes clusters on a host cluster via the official Loft Helm chart (chart 0.34.1).
**Currently deferred** (ADR-033): the OSS chart cannot sync HTTPRoutes to the host Gateway, so all teams
use namespace isolation. The module is retained for future use.

- Configurable resource sync, isolation (network policies, quotas, limit ranges), optional ingress
- **Key Variables**: `cluster_name`, `namespace`, `chart_version`, `vcluster_version`, `values`,
  `sync`, `isolation`, `ingress`, `storage_class`, `tags`

## Cross-Cloud Feature Parity

The platform achieves cross-cloud compatibility through a shared output contract on per-cloud modules
(`network_id`, `network_name`, `subnet_ids`, `kubernetes_subnet_id`, `create`) and cloud-agnostic shared
modules — **not** abstraction layers. Only AWS is implemented today; the Azure/GCP columns describe the
intended contract a second cloud would satisfy.

| Capability | AWS | Azure / GCP |
|------------|-----|-------------|
| VPC/VNet + subnets + routing + NAT | Implemented | Planned (same output contract) |
| Kubernetes networking | Implemented (EKS) | Planned (AKS / GKE) |
| Cross-cloud interface outputs + `create` toggle | Implemented | Planned |
| Cilium, ArgoCD, cert-manager, External Secrets, Kyverno, observability, Crossplane | Implemented (shared) | Reused as-is when the cloud lands |

## Module Usage Guidelines

1. **Input Variables**: review the module's `README.md` for required/optional inputs.
2. **Dependencies**: units wire modules via Terragrunt `dependency` blocks (with `mock_outputs`).
3. **Outputs**: reference module outputs from dependent units.
4. **Testing**: Terratest (Go) under `infra/tests/aws/<module>/` — plan-only where apply is unsafe.
5. **`create` toggle**: every resource-creating module supports `create = false`.

## Next Steps

For module design conventions, see [Module Design](13-module-design.md).

## Related Documentation

- [Infrastructure as Code Approach](03-infrastructure-as-code.md)
- [Deployment Workflows](14-deployment-workflows.md) · [Testing Strategy](15-testing-strategy.md)
- [Module Design Principles](13-module-design.md)
- [Architecture Overview](02-architecture-overview.md) · [Network Topology](07-network-topology.md)
- [Kubernetes Network Design](08-kubernetes-network-design.md) · [Security Architecture](09-security-architecture.md)
- [Naming Conventions](11-naming-conventions.md) · [Tagging Strategy](12-tagging-strategy.md)
- [README Standards](README-STANDARDS.md)
