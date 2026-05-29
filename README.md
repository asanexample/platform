# Multi-Cloud Platform Infrastructure

Infrastructure-as-code for a multi-cloud platform using OpenTofu and Terragrunt.
AWS is the primary deployed platform (4 accounts, 2 EKS clusters); Azure and GCP
modules exist but are not actively deployed. The platform provides tenant isolation,
GitOps delivery, private cluster access, and compliance guardrails through a layered
module architecture.

## Quick Start

```bash
# Prerequisites: OpenTofu >= 1.6.0, Terragrunt >= 0.69.0, AWS CLI v2

# Authenticate
aws sso login --profile management

# Bootstrap the full platform stack
platctl bootstrap

# Or deploy a single unit
cd infra/live/aws/platform/us-east-1/platform/eks
AWS_PROFILE=management terragrunt apply

# Validate deployed infrastructure
platctl validate

# Configure kubectl contexts
platctl kubeconfig
```

## Repository Layout

```text
platform/
├── cmd/platctl/                 # Go CLI for platform operations (bootstrap, teardown, validate)
├── docs/                        # User-facing documentation
│   ├── adrs/                    # 38 architecture decision records
│   ├── architecture/            # System design, tenant model, config hierarchy
│   ├── compliance/              # SOC2/HIPAA/PCI-DSS control mappings
│   ├── runbooks/                # Operational procedures
│   └── troubleshooting/         # Known issues and solutions
├── infra/
│   ├── live/                    # Terragrunt live configurations
│   │   ├── aws/
│   │   │   ├── mgmt/           # Management account (Organizations, state, IAM Identity Center)
│   │   │   ├── platform/       # Platform account (EKS, ArgoCD, Tailscale, TGW hub)
│   │   │   ├── preprod/        # Preprod account (EKS, tenants, ingress, TGW spoke)
│   │   │   ├── prod/           # Prod account (networking defined, not yet deployed)
│   │   │   └── test/           # Test account (GitHub OIDC for Terratest CI)
│   │   ├── azure/              # Azure environments (dev, ops) — not actively deployed
│   │   └── gcp/                # GCP stub (networking + naming only)
│   ├── modules/                # Reusable OpenTofu modules
│   │   ├── aws/                # 17 AWS modules
│   │   ├── azure/              # 24 Azure modules
│   │   ├── cloudflare/         # 1 Cloudflare module
│   │   ├── gcp/                # 2 GCP modules
│   │   └── (shared)            # 15 cloud-agnostic modules (cilium, argocd, tenant, etc.)
│   ├── tests/                  # Terratest integration tests (Go)
│   └── root.hcl                # Root Terragrunt config (cloud-aware state routing)
└── scripts/                    # Helper scripts (eks-tunnel, bootstrap, teardown)
```

## AWS Accounts

| Account | ID | Purpose |
|---------|------|---------|
| Management | <MGMT_ACCOUNT_ID> | AWS Organizations, SCPs, IAM Identity Center, Terraform state |
| Platform | <PLATFORM_ACCOUNT_ID> | Shared services: EKS, ArgoCD, Tailscale, TGW hub, ECR |
| PreProd | <PREPROD_ACCOUNT_ID> | Workloads: EKS, tenant namespaces, ingress, TGW spoke |
| Prod | <PROD_ACCOUNT_ID> | Production workloads (networking defined, not yet deployed) |

Cross-account access uses purpose-built IAM roles (PlatformAdmin, PlatformDeployer,
DeveloperAccess, TerraformStateAccess). `OrganizationAccountAccessRole` retained as
break-glass only.

## Platform Stack

### Deployed Infrastructure (AWS)

**Platform account** — shared services cluster:

- EKS cluster (private API, BYOCNI) with Cilium 1.19.4
- ArgoCD for GitOps delivery with Dex SAML SSO
- Tailscale Operator for VPN access to private clusters
- Transit Gateway hub for cross-VPC connectivity
- Cross-VPC DNS for private EKS endpoint resolution
- Gateway API (internal NLB) for platform service ingress
- cert-manager, ExternalDNS, External Secrets Operator

**Preprod account** — workload cluster:

- EKS cluster with Cilium, Gateway API (public NLB)
- Tenant isolation via namespaces with default-deny NetworkPolicies
- ArgoCD Applications and PR preview ApplicationSets per team
- ECR cross-account image pull, GitHub OIDC for CI/CD
- Transit Gateway spoke connected to platform hub

### Deployment Order

The full dependency DAG is documented in [CLAUDE.md](CLAUDE.md). The preferred
deployment method is `platctl bootstrap`, which resolves the DAG automatically.

## Modules

### Shared (15 modules)

| Module | Description |
|--------|-------------|
| [argocd](infra/modules/argocd/) | ArgoCD Helm deployment with HA, RBAC, Dex SSO |
| [argocd-apps](infra/modules/argocd-apps/) | Multi-tenant AppProjects, Applications, PR preview ApplicationSets |
| [argocd-bootstrap](infra/modules/argocd-bootstrap/) | Bootstrap App-of-Apps for foundational services |
| [argocd-clusters](infra/modules/argocd-clusters/) | Remote cluster registration |
| [cert-manager](infra/modules/cert-manager/) | cert-manager Helm with IRSA for DNS-01 challenges |
| [cilium](infra/modules/cilium/) | Cilium CNI with cloud-specific config, Gateway API, Hubble |
| [external-dns](infra/modules/external-dns/) | ExternalDNS Helm with IRSA |
| [external-secrets](infra/modules/external-secrets/) | External Secrets Operator Helm with IRSA |
| [gateway-config](infra/modules/gateway-config/) | ClusterIssuer, Gateway, HTTPRoutes |
| [policy](infra/modules/policy/) | Kyverno policy engine |
| [secret-stores](infra/modules/secret-stores/) | ClusterSecretStore for AWS Secrets Manager and SSM |
| [tailscale](infra/modules/tailscale/) | Tailscale Operator, subnet router, split DNS |
| [tailscale-admin](infra/modules/tailscale-admin/) | Tailnet ACL and OAuth client management |
| [tenant](infra/modules/tenant/) | Namespace isolation with quotas, limits, network policies |
| [vcluster](infra/modules/vcluster/) | vCluster Helm (deferred — ADR-033) |

### AWS (17 modules)

| Module | Description |
|--------|-------------|
| [cloudtrail](infra/modules/aws/cloudtrail/) | Audit logging with S3, KMS, secrets alarms |
| [cross-vpc-dns](infra/modules/aws/cross-vpc-dns/) | Cross-VPC DNS for private EKS endpoints |
| [ecr](infra/modules/aws/ecr/) | ECR with lifecycle policies and cross-account access |
| [eks](infra/modules/aws/eks/) | EKS cluster with BYOCNI, KMS, OIDC, access entries |
| [eks-addons](infra/modules/aws/eks-addons/) | EKS managed add-ons with IRSA |
| [eks-node-group](infra/modules/aws/eks-node-group/) | EKS managed node groups |
| [github_oidc](infra/modules/aws/github_oidc/) | GitHub Actions OIDC federation |
| [iam_roles](infra/modules/aws/iam_roles/) | Purpose-built IAM roles |
| [identity_center](infra/modules/aws/identity_center/) | IAM Identity Center permission sets |
| [naming](infra/modules/aws/naming/) | Resource naming conventions |
| [networking](infra/modules/aws/networking/) | VPC, subnets, NAT, flow logs (3 topology modes) |
| [organizations](infra/modules/aws/organizations/) | AWS Organizations with OUs and SCPs |
| [route53](infra/modules/aws/route53/) | Route53 hosted zones |
| [route53_delegation](infra/modules/aws/route53_delegation/) | NS record delegation between zones |
| [ssm-bastion](infra/modules/aws/ssm-bastion/) | SSM bastion for private cluster access |
| [state_bootstrap](infra/modules/aws/state_bootstrap/) | S3 + DynamoDB for Terraform state |
| [transit-gateway](infra/modules/aws/transit-gateway/) | TGW hub/spoke for cross-VPC connectivity |

### Azure (24 modules), GCP (2 modules), Cloudflare (1 module)

See [infra/modules/README.md](infra/modules/README.md) for the full catalog.

## Key Design Decisions

| Decision | ADR |
|----------|-----|
| Multi-cloud Terragrunt monorepo | [ADR-001](docs/adrs/001-multi-cloud-terragrunt-structure.md) |
| Cilium as cross-cloud CNI | [ADR-008](docs/adrs/008-cilium-as-cross-cloud-cni.md) |
| EKS component separation (BYOCNI ordering) | [ADR-009](docs/adrs/009-eks-component-separation.md) |
| Private EKS API endpoint | [ADR-010](docs/adrs/010-private-eks-api-endpoint.md) |
| Tailscale for VPN access | [ADR-011](docs/adrs/011-tailscale-for-private-cluster-access.md) |
| Gateway API over Ingress | [ADR-017](docs/adrs/017-gateway-api-over-ingress.md) |
| ArgoCD for GitOps | [ADR-021](docs/adrs/021-argocd-for-gitops.md) |
| Namespace tenant isolation | [ADR-027](docs/adrs/027-hybrid-tenant-isolation-model.md) |
| Multi-app tenant model | [ADR-031](docs/adrs/031-multi-app-tenant-model.md) |
| PR preview environments | [ADR-032](docs/adrs/032-pr-preview-environments.md) |
| Transit Gateway hub/spoke | [ADR-034](docs/adrs/034-transit-gateway-cross-account-connectivity.md) |
| platctl CLI | [ADR-038](docs/adrs/038-platctl-cli-for-platform-operations.md) |

All 38 ADRs: [docs/adrs/](docs/adrs/)

## Testing

Tests use Terratest (Go) and live in `infra/tests/aws/<module>/`.

```bash
cd infra/tests/aws/networking && go test -v -timeout 30m
```

CI runs via GitHub Actions with OIDC federation — no stored credentials.

## Documentation

| Document | Description |
|----------|-------------|
| [Onboarding Guide](docs/onboarding.md) | New team member quickstart |
| [User Guide](docs/user-guide.md) | Complete reference for deployments and day-2 ops |
| [Deploy App to Preprod](docs/runbooks/deploy-app-preprod.md) | Developer guide: manifests, ECR, ArgoCD |
| [Tenant Onboarding](docs/runbooks/tenant-onboarding.md) | Add/remove teams via `teams.hcl` |
| [EKS Cluster Access](docs/runbooks/eks-cluster-access.md) | kubectl setup for engineers |
| [Architecture Decisions](docs/adrs/) | 38 ADRs documenting every significant choice |
| [Compliance Mappings](docs/compliance/) | SOC2, HIPAA, PCI-DSS control coverage |
