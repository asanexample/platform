# Architecture Overview

## Design Principles

1. **Infrastructure as Code** -- all infrastructure is defined in
   OpenTofu modules managed by Terragrunt. No manual configuration.
2. **Modularity** -- infrastructure is decomposed into single-purpose
   modules (networking, EKS, IAM roles, etc.) composed via Terragrunt
   dependency graphs.
3. **Multi-cloud portability** -- shared modules (Cilium, ArgoCD,
   cert-manager, etc.) are cloud-agnostic. Cloud-specific modules live
   under `infra/modules/{aws,azure,gcp}/`. Live units handle
   cloud-specific provider configuration.
4. **Hierarchical configuration** -- settings are defined at the broadest
   applicable layer (cloud, environment, region, workload) and merged at
   apply time. Later layers override earlier ones.
5. **Least privilege** -- IAM roles are purpose-built (PlatformAdmin,
   PlatformDeployer, DeveloperAccess). SCPs enforce guardrails at the
   organization level.
6. **BYOCNI** -- Cilium replaces the default CNI on all clouds (ENI mode
   on AWS, overlay on Azure) for consistent network policy, observability,
   and eBPF-based networking.

## Implementation Status

| Cloud | Status | What's Deployed |
|-------|--------|-----------------|
| AWS | **Production** | Full EKS platform in us-east-1: networking, IAM, EKS, Cilium, ArgoCD, cert-manager, external-dns, external-secrets, Tailscale VPN, gateway ingress. Preprod and prod accounts have networking only. |
| Azure | **Development** | AKS clusters in dev (eastus) and ops (westus) with full observability stack (Grafana, Prometheus, Log Analytics), Front Door, storage, container registry. |
| GCP | **Scaffolded** | Naming and networking modules exist. Live config for ops/us-east1 is defined but no units are deployed. |

## AWS Architecture

### Account Structure

The AWS Organization has five accounts across three organizational units:

```mermaid
graph TD
    Root["Root (Management)<br/><MGMT_ACCOUNT_ID>"]
    Root --> Platform_OU["Platform OU"]
    Root --> Workloads_OU["Workloads OU"]

    Platform_OU --> Platform["Platform<br/><PLATFORM_ACCOUNT_ID>"]
    Platform_OU --> Test["Test<br/><TEST_ACCOUNT_ID>"]

    Workloads_OU --> Preprod_OU["Preprod OU"]
    Workloads_OU --> Prod_OU["Prod OU"]
    Workloads_OU --> Regulated_OU["Regulated OU"]

    Preprod_OU --> Preprod["Preprod<br/><PREPROD_ACCOUNT_ID>"]
    Prod_OU --> Prod["Prod<br/><PROD_ACCOUNT_ID>"]
```

| Account | ID | Purpose |
|---------|-----|---------|
| Management | <MGMT_ACCOUNT_ID> | Organizations, Identity Center, Terraform state, GitHub OIDC |
| Platform | <PLATFORM_ACCOUNT_ID> | EKS cluster, platform services, IAM roles |
| Test | <TEST_ACCOUNT_ID> | Terratest CI execution (GitHub Actions) |
| Preprod | <PREPROD_ACCOUNT_ID> | Workload pre-production (networking only) |
| Prod | <PROD_ACCOUNT_ID> | Workload production (networking only) |

**Service Control Policies** are attached per OU:

- **Root**: baseline-guardrails, protect-security-services, enforce-encryption, deny-regions
- **Platform**: protect-data-and-network
- **Workloads**: protect-data-and-network, require-tagging, restrict-iam-users

### IAM Roles

| Role | Account | Trust | Purpose |
|------|---------|-------|---------|
| PlatformAdmin | Platform | SSO from mgmt + platform | kubectl, SSM tunnel, cluster debugging (4hr sessions) |
| PlatformDeployer | Platform | mgmt account | Terragrunt apply, Helm/K8s providers (2hr sessions) |
| DeveloperAccess | Platform | SSO from mgmt + platform | Namespace-scoped kubectl (4hr sessions) |
| TerraformStateAccess | Management | PlatformDeployer | S3 state bucket + DynamoDB lock table |

Authentication flows through AWS IAM Identity Center (SSO) with three
permission sets (AdministratorAccess, PowerUserAccess, ReadOnlyAccess)
assigned to groups (Admins, Developers, ReadOnly).

### Network Topology

The platform account VPC uses a multi-AZ, multi-tier subnet layout:

```mermaid
graph TB
    subgraph VPC ["VPC 10.100.0.0/16"]
        subgraph AZ1 ["us-east-1a"]
            k1["kubernetes /26"]
            e1["endpoints /26"]
            f1["firewall /26"]
            s1["services /27"]
            p1["public /28"]
            t1["transit /28"]
        end
        subgraph AZ2 ["us-east-1b"]
            k2["kubernetes /26"]
            e2["endpoints /26"]
            f2["firewall /26"]
            s2["services /27"]
            p2["public /28"]
            t2["transit /28"]
        end
        subgraph AZ3 ["us-east-1c"]
            k3["kubernetes /26"]
            e3["endpoints /26"]
            f3["firewall /26"]
            s3["services /27"]
            p3["public /28"]
            t3["transit /28"]
        end
        IGW["Internet Gateway"]
        NAT["NAT Gateway (single)"]
        S3EP["S3 Gateway Endpoint"]
    end
```

| Subnet Tier | Size | Scope | Purpose |
|-------------|------|-------|---------|
| kubernetes | /26 (62 IPs) | Private | EKS node groups and pods |
| endpoints | /26 (62 IPs) | Private | VPC endpoints, private links |
| firewall | /26 (62 IPs) | Private | Network firewall (future) |
| services | /27 (30 IPs) | Private | Internal services, load balancers |
| public | /28 (14 IPs) | Public | NAT gateway, bastion, public ALBs |
| transit | /28 (14 IPs) | Private | Cross-account/cross-region peering (future) |

VPC Flow Logs ship to CloudWatch with 30-day retention. An S3 gateway
endpoint reduces NAT costs for S3 traffic.

CIDR allocation follows a per-environment `/16` scheme:

| Environment | VPC CIDR |
|-------------|----------|
| Platform | `10.100.0.0/16` |
| Preprod | `10.101.0.0/16` |
| Prod | `10.102.0.0/16` |

### EKS Cluster and Platform Services

The platform account runs a single EKS cluster (`platform-use1-eks`,
Kubernetes 1.35) with a private-only API endpoint. Developer access is
via Tailscale VPN; SSM tunnel is the fallback.

```mermaid
graph LR
    Dev["Developer Laptop<br/>(Tailscale client)"] --> TS["Tailscale<br/>Subnet Router"]
    TS --> API["EKS Private API<br/>Endpoint"]
    API --> CP["Control Plane"]

    subgraph Node Groups
        SYS["System Nodes<br/>2x t3.large"]
        WRK["Workload Nodes<br/>1-6x t3.large"]
    end

    CP --> SYS
    CP --> WRK
```

**Node groups:**

| Group | Instance Type | Min | Max | Labels |
|-------|--------------|-----|-----|--------|
| system | t3.large | 2 | 4 | `node-role=system` |
| workload | t3.large | 1 | 6 | `node-role=workload` |

**Platform services deployed via Helm:**

| Service | Chart Version | Purpose |
|---------|--------------|---------|
| Cilium | 1.17.2 | CNI (ENI mode, native routing, Hubble observability) |
| ArgoCD | 9.5.14 | GitOps continuous delivery, SSO via Identity Center SAML |
| cert-manager | 1.17.1 | TLS certificate management (Let's Encrypt, DNS01 via Route53) |
| external-dns | 1.16.1 | DNS record sync to Route53 |
| external-secrets | 0.14.3 | Secrets from AWS Secrets Manager + SSM Parameter Store |
| Kyverno | 3.3.7 | Policy engine (pod security, image provenance) |
| Tailscale Operator | 1.96.5 | Mesh VPN subnet router for private cluster access |

All Helm chart versions are pinned in `infra/live/aws/_versions.hcl`.

**Deployment dependency graph:**

```mermaid
graph TD
    NET["networking"] --> EKS["eks"]
    IAM["iam-roles"] --> EKS
    EKS --> CIL["cilium"]
    CIL --> NG["node-groups"]
    NG --> SSM["ssm-bastion"]

    EKS --> EA["eks-addons"]
    CIL --> EA
    NG --> EA

    NG --> CM["cert-manager"]
    NG --> ED["external-dns"]
    NG --> ES["external-secrets"]
    NG --> ARGO["argocd"]
    NG --> TS["tailscale"]
    R53["route53"] --> CM
    R53 --> ED

    CIL --> GW["gateway-config"]
    CM --> GW
    ED --> GW
    ARGO --> GW
    R53 --> GW

    TSA["tailscale-admin<br/>(no cluster deps)"]
```

EKS uses BYOCNI (`bootstrap_self_managed_addons = false`), so Cilium
must be deployed before node groups can join the cluster. EKS managed
add-ons (coredns) are in a separate `eks-addons` unit that depends on
Cilium and node-groups, since addon pods need the CNI to schedule.

### DNS

Route53 hosts the `aws.refplat.org` subdomain. Cloudflare manages the
parent `refplat.org` zone and delegates via NS records. external-dns
syncs Kubernetes ingress/service records to Route53. cert-manager uses
Route53 DNS01 challenges for Let's Encrypt certificates.

### Private Cluster Access

The EKS API endpoint is private-only. Two access methods:

1. **Tailscale VPN** (primary) -- the Tailscale Operator runs as a subnet
   router advertising `10.100.0.0/16` to the tailnet. Split DNS routes
   `*.eks.amazonaws.com` to the VPC DNS resolver. Developers install
   Tailscale, join the tailnet, and `kubectl` works directly.
2. **SSM tunnel** (fallback) -- `scripts/eks-tunnel.sh` opens a port
   forward through the SSM bastion to the cluster endpoint.

## Azure Architecture

Azure has 24 modules covering AKS, networking, identity, observability,
storage, and Front Door. Two environments are deployed:

| Environment | Subscription | Region |
|-------------|-------------|--------|
| dev | `db4f1d99-0ec0-44eb-90de-41975f9bb68b` | eastus |
| ops | `9dc5edc4-8c4e-41a1-a4f8-2183c4e91954` | westus |

Each environment deploys a full stack:

```mermaid
graph TD
    RG["resource_group"] --> NET["networking"]
    RG --> KV["key_vault"]
    NET --> AKS["aks_core"]
    AKS --> NP["aks_node_pools"]
    AKS --> CIL["cilium"]

    RG --> ACR["container_registry"]
    RG --> LA["log_analytics"]
    LA --> DS["diagnostic_settings"]
    RG --> MW["monitor_workspace"]
    MW --> MG["managed_grafana"]
    MW --> PDCR["prometheus_dcr"]
    RG --> MA["monitor_alerts"]

    RG --> FDP["frontdoor_profile"]
    FDP --> FDE["frontdoor_endpoint"]
    FDE --> FDPL["frontdoor_private_link"]

    RG --> STR["storage"]
    STR --> SR["storage_roles"]
```

Key differences from AWS:

- **Identities**: User-assigned managed identities with federated
  credentials (no IRSA equivalent needed -- Azure handles this natively)
- **Observability**: Azure-managed Grafana + Prometheus DCR + Log
  Analytics (vs self-managed on AWS)
- **Ingress**: Azure Front Door with private link backends (vs
  gateway-config with Cilium on AWS)
- **Cilium**: BYOCNI overlay mode (vs ENI mode on AWS)

## GCP Architecture

GCP has two modules (`naming`, `networking`) that mirror the cross-cloud
interface contracts. Live configuration exists for an ops environment in
us-east1 with CIDR `10.102.0.0/16` and 15 planned subnets, but no units
are deployed yet.

## Configuration Hierarchy

All clouds share the same layered configuration pattern. Each layer is a
file that Terragrunt loads and merges:

```mermaid
graph TD
    ROOT["root.hcl<br/>State backend, providers"] --> COMMON["common.hcl<br/>Cloud-level defaults, tags"]
    COMMON --> ENV["env.hcl<br/>Account/subscription, environment tags"]
    ENV --> REGION["region.hcl<br/>Region name, AZs"]
    REGION --> NETWORK["network.hcl<br/>CIDR, subnet tiers"]
    NETWORK --> WORKLOAD["workload.hcl<br/>Workload name, compliance tier"]
    WORKLOAD --> BASE["_base.hcl<br/>merge() all layers"]
    BASE --> MODULE["terragrunt.hcl<br/>Module inputs"]
```

Tags, module sources, and Helm versions are composed from these layers.
`_base.hcl` merges tags and exposes all computed locals to live units via
`include.base.locals.*`. Safety validations assert that directory paths
match the declared environment and account ID.

See [Configuration Hierarchy](../../docs/architecture/config-hierarchy.md)
for the full breakdown.

## State Management

| Cloud | Backend | Location |
|-------|---------|----------|
| AWS | S3 + DynamoDB | `tfstate-mgmt-<MGMT_ACCOUNT_ID>` bucket in us-east-1, `terraform-locks` table |
| Azure | Azure Blob Storage | `tfstatemulticloud` storage account, `terraformstate` container |

State paths follow the directory structure:
`{env}/{region}/{workload}/{module}/terraform.tfstate`. The S3 bucket and
DynamoDB table are bootstrapped by the `state-bootstrap` unit in the
management account. Encryption is enabled on both backends.

The `TerraformStateAccess` role in the management account grants the
`PlatformDeployer` role cross-account access to the state bucket and
lock table.

## Technology Stack

| Component | Version |
|-----------|---------|
| OpenTofu | >= 1.6.0 (CI uses 1.9.0) |
| Terragrunt | Latest (installed in CI from GitHub releases) |
| AWS Provider | 6.45.0 |
| Azure Provider | 4.25.0 |
| GCP Provider | 6.26.0 |
| Helm Provider | >= 3.0 |
| Kubernetes Provider | >= 2.35.0 |
| Tailscale Provider | ~> 0.29 |
| Kubernetes | 1.35 (EKS) |
| Go (tests) | 1.22+ |

## Next Steps

Continue to [Infrastructure as Code Approach](03-infrastructure-as-code.md)
to understand how the architecture is implemented using OpenTofu and
Terragrunt.
