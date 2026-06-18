# Architecture Decision Records

Each ADR captures one significant decision: its context, the choice, and the consequences. They are
append-only — a decision is changed by a *new* ADR that supersedes or refines an earlier one, not by
rewriting it. This index is the canonical list; keep it in sync when adding an ADR.

**Status legend:** `Accepted` (in force) · `Proposed` (direction agreed, not yet built / rebuild-gated) ·
`Superseded` (replaced by a later ADR).

## Foundation & AWS Org

| ADR | Status |
|-----|--------|
| [ADR-001: Multi-Cloud Terragrunt Monorepo Structure](001-multi-cloud-terragrunt-structure.md) | Accepted |
| [ADR-002: AWS State Storage in S3 with Cloud-Aware Routing](002-aws-state-storage.md) | Accepted |
| [ADR-003: Service Control Policy Design Philosophy](003-scp-design-philosophy.md) | Accepted |
| [ADR-004: AWS Account Management Strategy](004-account-management-strategy.md) | Accepted |
| [ADR-005: Organizational Unit Hierarchy Design](005-ou-hierarchy-design.md) | Accepted |
| [ADR-006: State Bootstrap Pattern](006-state-bootstrap-pattern.md) | Accepted |
| [ADR-007: Platform IAM Role Model](007-iam-role-model.md) | Accepted |

## Networking & Connectivity

| ADR | Status |
|-----|--------|
| [ADR-015: CIDR Allocation Strategy](015-cidr-allocation-strategy.md) | Accepted |
| [ADR-022: DNS Architecture — Route53 with Cloudflare Delegation](022-dns-architecture.md) | Accepted |
| [ADR-030: Route53 Subdomain Delegation for Environment DNS](030-route53-subdomain-delegation.md) | Accepted |
| [ADR-034: Transit Gateway for Cross-Account VPC Connectivity](034-transit-gateway-cross-account-connectivity.md) | Accepted |
| [ADR-035: Cross-VPC DNS Resolution for Private EKS Endpoints](035-cross-vpc-dns-resolution.md) | Accepted |

## Cluster & Platform Runtime

| ADR | Status |
|-----|--------|
| [ADR-008: Cilium as Cross-Cloud CNI](008-cilium-as-cross-cloud-cni.md) | Accepted |
| [ADR-009: EKS Component Separation](009-eks-component-separation.md) | Accepted |
| [ADR-010: Private-Only EKS API Endpoint](010-private-eks-api-endpoint.md) | Accepted |
| [ADR-011: Tailscale Operator for Private Cluster Access](011-tailscale-for-private-cluster-access.md) | Accepted |
| [ADR-016: OpenTofu over HashiCorp Terraform](016-opentofu-over-terraform.md) | Accepted |
| [ADR-017: Gateway API over Traditional Ingress](017-gateway-api-over-ingress.md) | Accepted |
| [ADR-020: SSM Session Manager Bastion over SSH Bastion](020-ssm-bastion-over-ssh.md) | Accepted |
| [ADR-021: ArgoCD for GitOps Delivery](021-argocd-for-gitops.md) | Accepted |
| [ADR-023: EKS Managed Node Groups over Self-Managed or Karpenter](023-managed-node-groups.md) | Accepted |
| [ADR-038: platctl CLI for Platform Operations](038-platctl-cli-for-platform-operations.md) | Accepted |
| [ADR-065: Self-Hosted GitHub Actions Runners (ARC) on the Platform Cluster](065-self-hosted-github-actions-runners-arc.md) | Accepted |

## Secrets & Config

| ADR | Status |
|-----|--------|
| [ADR-019: External Secrets Operator for Secrets Management](019-external-secrets-operator.md) | Accepted |
| [ADR-024: Secrets Management Architecture](024-secrets-management-architecture.md) | Accepted |
| [ADR-025: Secret Naming Convention and Path Hierarchy](025-secret-naming-convention.md) | Accepted |
| [ADR-026: Cross-Account Secret Isolation](026-cross-account-secret-isolation.md) | Accepted |
| [ADR-037: CloudTrail for Secrets Audit Logging](037-cloudtrail-audit-logging.md) | Accepted |
| [ADR-066: SOPS-Encrypted Config Secrets in Git (KMS)](066-sops-encrypted-config-secrets.md) | Proposed |
| [ADR-070: Tenant Application Config & Secrets](070-tenant-app-config-and-secrets.md) | Proposed |

## Tenancy, Isolation & Policy

| ADR | Status |
|-----|--------|
| [ADR-013: Compliance Tier Model](013-compliance-tier-model.md) | Accepted |
| [ADR-014: Kyverno as Policy Engine](014-kyverno-as-policy-engine.md) | Accepted |
| [ADR-027: Hybrid Tenant Isolation Model](027-hybrid-tenant-isolation-model.md) | Accepted |
| [ADR-028: ECR Cross-Account Container Registry](028-ecr-cross-account-container-registry.md) | Accepted |
| [ADR-029: Preprod Public Ingress via Gateway API](029-preprod-public-ingress-gateway-api.md) | Accepted |
| [ADR-031: Multi-App Tenant Model](031-multi-app-tenant-model.md) | Accepted |
| [ADR-032: PR Preview Environments](032-pr-preview-environments.md) | Accepted |
| [ADR-033: Defer vCluster Tenant Support](033-defer-vcluster-tenant-support.md) | Accepted |
| [ADR-046: Adopt the BACK Stack for Developer Self-Service](046-back-stack-for-developer-self-service.md) | Accepted |
| [ADR-048: Federated, Per-Cluster Crossplane for Tenant Provisioning](048-federated-per-cluster-crossplane.md) | Accepted |
| [ADR-049: Multi-Tenancy Model — Team, Tenant, and Zone](049-tenant-model-team-tenant-zone.md) | Accepted (Zone/Customer partly superseded by ADR-067) |
| [ADR-058: Per-Cloud Tenant Composition Strategy](058-per-cloud-tenant-composition-strategy.md) | Proposed |
| [ADR-060: Tenant App Hostname Convention — Derive and Inject](060-tenant-app-hostname-convention.md) | Accepted |
| [ADR-061: Tenant Ingress & Custom Domain Strategy](061-tenant-ingress-and-custom-domain-strategy.md) | Accepted |
| [ADR-062: Self-Service Tenant Provisioning (Backstage + GitOps) & Its Security Model](062-self-service-tenant-provisioning.md) | Proposed |
| [ADR-063: Team as a First-Class Git-Native Object](063-team-as-first-class-git-object.md) | Proposed |
| [ADR-067: IDP Domain Model — Team / Product / Service / Environment / Customer](067-idp-domain-model.md) | Proposed |
| [ADR-069: Delivery Source-of-Truth — Product Registry + Environment Claims](069-delivery-source-of-truth-product-environment.md) | Proposed |

## Workload & Human Identity

| ADR | Status |
|-----|--------|
| [ADR-012: ArgoCD SSO via Dex and SAML](012-argocd-sso-via-dex-saml.md) | Accepted |
| [ADR-018: IRSA for Pod-Level AWS Identity](018-irsa-for-pod-identity.md) | Superseded by ADR-047 |
| [ADR-039: Per-Team Developer RBAC](039-per-team-developer-rbac.md) | Accepted |
| [ADR-040: Platform Engineer Access Model](040-platform-engineer-access-model.md) | Accepted |
| [ADR-041: EKS Pod Identity for Tenant Workloads](041-pod-identity-for-tenant-workloads.md) | Accepted |
| [ADR-047: EKS Pod Identity as the Standard for Pod AWS Identity](047-pod-identity-as-aws-identity-standard.md) | Accepted |
| [ADR-052: Centralized Dex SSO Broker](052-centralized-dex-sso-broker.md) | Accepted (Dex retired; see ADR-053/059) |
| [ADR-053: Identity & Cross-System Authorization Strategy](053-identity-and-cross-system-authorization-strategy.md) | Accepted |
| [ADR-059: Identity Topology — Keycloak as the Pluggable Identity Seam](059-identity-topology-pluggable-idp-seam.md) | Accepted |
| [ADR-068: Product-Scoped & Cross-Team Access Model](068-product-scoped-and-cross-team-access-model.md) | Proposed |

## Supply Chain & Delivery

| ADR | Status |
|-----|--------|
| [ADR-036: GitHub Actions OIDC Federation for CI/CD](036-github-actions-oidc-federation.md) | Accepted |
| [ADR-042: Isolated Build Provenance for SLSA Build L3](042-isolated-build-provenance-slsa-l3.md) | Accepted |
| [ADR-050: Shared `build-sign` Reusable Workflow + Shared-Signer Policy Model](050-shared-build-sign-reusable-workflow.md) | Accepted |
| [ADR-056: Progressive Delivery & Safe Rollback](056-progressive-delivery-and-safe-rollback.md) | Proposed |
| [ADR-071: Image-Digest Promotion via the Control Plane (Protected-Main Delivery)](071-digest-promotion-via-control-plane.md) | Accepted |

## Developer Portal & Experience

| ADR | Status |
|-----|--------|
| [ADR-051: Backstage as the Developer Portal](051-backstage-developer-portal.md) | Accepted |
| [ADR-064: Backstage Provisioning Visibility & Developer Experience](064-backstage-provisioning-visibility.md) | Proposed |

## Self-Service Resources & Agentic Workloads

| ADR | Status |
|-----|--------|
| [ADR-073: Self-Service Cloud Resources (the resource paved road)](073-self-service-cloud-resources.md) | Accepted |
| [ADR-074: Agentic Workloads — a Governed Platform for Running AI Agents](074-agentic-workloads-platform.md) | Proposed |
| [ADR-075: The Resource Agent — Conversational Self-Service (ADR-073 Phase B)](075-resource-agent.md) | Proposed |

## Observability, Resilience & Compliance Assurance

| ADR | Status |
|-----|--------|
| [ADR-043: Self-Hosted Prometheus/Grafana Observability Stack](043-self-hosted-observability-stack.md) | Accepted |
| [ADR-044: Grafana Mimir for Durable, Multi-Tenant Metrics Storage](044-mimir-durable-multi-tenant-metrics.md) | Accepted |
| [ADR-045: Falco for Runtime Threat Detection](045-falco-runtime-threat-detection.md) | Accepted |
| [ADR-076: Agent / GenAI Observability](076-agent-observability.md) | Proposed |
| [ADR-054: Platform Resilience & Business Continuity](054-platform-resilience-and-business-continuity.md) | Proposed |
| [ADR-055: Compliance Assurance & Continuous Control Evidence](055-compliance-assurance-and-continuous-control-evidence.md) | Proposed |
| [ADR-057: Service Identity & East-West Zero Trust (mTLS)](057-service-identity-and-east-west-zero-trust.md) | Proposed |
