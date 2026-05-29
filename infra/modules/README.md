# Terraform Modules

Reusable Terraform/OpenTofu modules for the platform. Cloud-agnostic modules live at the top level; cloud-specific modules are nested under their provider directory.

## Organization

```text
modules/
├── aws/           # AWS-specific modules
├── azure/         # Azure-specific modules
├── cloudflare/    # Cloudflare modules
├── gcp/           # GCP modules (stubbed)
└── <shared>/      # Cloud-agnostic modules (cilium, argocd, tenant, etc.)
```

## Shared Modules

| Module | Description |
|--------|-------------|
| [argocd](argocd/) | ArgoCD Helm deployment with HA, RBAC, Dex SSO |
| [argocd-apps](argocd-apps/) | Multi-tenant AppProjects, Applications, PR preview ApplicationSets |
| [argocd-clusters](argocd-clusters/) | Remote cluster registration via labeled K8s Secrets |
| [cert-manager](cert-manager/) | cert-manager Helm with IRSA for DNS-01 challenges |
| [cilium](cilium/) | Cilium CNI with cloud-specific config (AWS/Azure/GCP), Gateway API, Hubble |
| [external-dns](external-dns/) | ExternalDNS Helm with IRSA, Gateway API source support |
| [external-secrets](external-secrets/) | External Secrets Operator Helm with IRSA |
| [gateway-config](gateway-config/) | ClusterIssuer, Cilium Gateway, HTTPRoutes, HTTP-to-HTTPS redirect |
| [policy](policy/) | Kyverno Helm with compliance-tier policies |
| [secret-stores](secret-stores/) | ClusterSecretStore for Secrets Manager and SSM Parameter Store |
| [tailscale](tailscale/) | Tailscale Operator, subnet router, split DNS |
| [tailscale-admin](tailscale-admin/) | Tailnet ACL management, OAuth client provisioning |
| [tenant](tenant/) | Namespace/vCluster tenant isolation with quotas, limits, network policies |
| [vcluster](vcluster/) | vCluster Helm deployment (deferred -- see ADR-033) |

## AWS Modules

| Module | Description |
|--------|-------------|
| [cloudtrail](aws/cloudtrail/) | CloudTrail with S3 storage and KMS encryption |
| [cross-vpc-dns](aws/cross-vpc-dns/) | Cross-VPC DNS resolution for private EKS endpoints |
| [ecr](aws/ecr/) | ECR repositories with lifecycle policies and cross-account access |
| [eks](aws/eks/) | EKS cluster with BYOCNI, KMS, OIDC, access entries |
| [eks-addons](aws/eks-addons/) | EKS managed add-ons with IRSA role creation |
| [eks-node-group](aws/eks-node-group/) | EKS managed node groups |
| [github_oidc](aws/github_oidc/) | GitHub Actions OIDC federation for keyless CI/CD |
| [iam_roles](aws/iam_roles/) | Purpose-built IAM roles (PlatformAdmin, PlatformDeployer, DeveloperAccess) |
| [identity_center](aws/identity_center/) | AWS IAM Identity Center permission sets and assignments |
| [naming](aws/naming/) | Resource naming conventions for AWS |
| [networking](aws/networking/) | VPC, subnets, NAT, flow logs, three topology modes |
| [organizations](aws/organizations/) | AWS Organizations with OUs and SCPs |
| [route53](aws/route53/) | Route53 hosted zones |
| [route53_delegation](aws/route53_delegation/) | NS record delegation between Route53 zones |
| [ssm-bastion](aws/ssm-bastion/) | SSM Session Manager bastion for private cluster access |
| [state_bootstrap](aws/state_bootstrap/) | S3 + DynamoDB backend for Terraform state |
| [transit-gateway](aws/transit-gateway/) | Transit Gateway hub/spoke for cross-VPC connectivity |

## Azure Modules

| Module | Description |
|--------|-------------|
| [aks_core](azure/aks_core/) | AKS cluster with BYOCNI, system node pool, Azure AD RBAC |
| [aks_identity](azure/aks_identity/) | Managed identities for AKS and workload identity federation |
| [aks_node_pools](azure/aks_node_pools/) | Additional AKS node pools with auto-scaling |
| [client_config](azure/client_config/) | Data-only module exposing current Azure auth context |
| [container_registry](azure/container_registry/) | ACR with geo-replication, network rules, AKS integration |
| [diagnostic_settings](azure/diagnostic_settings/) | Azure Monitor diagnostic settings for log routing |
| [frontdoor_endpoint](azure/frontdoor_endpoint/) | Front Door endpoint and origin group |
| [frontdoor_private_link](azure/frontdoor_private_link/) | Front Door origin with Private Link |
| [frontdoor_profile](azure/frontdoor_profile/) | Front Door profile (Standard/Premium) |
| [identities](azure/identities/) | Full identity lifecycle with federated credentials |
| [key_vault](azure/key_vault/) | Key Vault with RBAC, network ACLs, private endpoint |
| [log_analytics](azure/log_analytics/) | Log Analytics workspace with solution packs |
| [managed_grafana](azure/managed_grafana/) | Azure Managed Grafana with Prometheus integration |
| [monitor_alerts](azure/monitor_alerts/) | Action groups, metric alerts, activity log alerts |
| [monitor_workspace](azure/monitor_workspace/) | Azure Monitor workspace for Prometheus metrics |
| [naming](azure/naming/) | CAF-aligned resource naming conventions |
| [networking](azure/networking/) | VNet, subnets, NSGs, private DNS for AKS |
| [private_dns](azure/private_dns/) | Private DNS zones with VNet links |
| [prometheus_dcr](azure/prometheus_dcr/) | Data Collection Rule for Prometheus metrics |
| [resource_group](azure/resource_group/) | Resource group with standardized tagging |
| [stack_base](azure/stack_base/) | Composite module: resource group + networking + key vault |
| [storage_account](azure/storage_account/) | Storage with lifecycle rules, CMK encryption, private endpoint |
| [storage_container](azure/storage_container/) | Blob containers with per-container role assignments |
| [storage_roles](azure/storage_roles/) | RBAC role assignments for storage |

## Cloudflare Modules

| Module | Description |
|--------|-------------|
| [dns_delegation](cloudflare/dns_delegation/) | NS record delegation from Cloudflare to cloud-hosted zones |

## GCP Modules

| Module | Description |
|--------|-------------|
| [naming](gcp/naming/) | Resource naming conventions for GCP |
| [networking](gcp/networking/) | VPC, subnets, firewall rules, Cloud NAT |

## Updating Documentation

Module READMEs use [terraform-docs](https://terraform-docs.io/) for auto-generated inputs/outputs. To regenerate:

```bash
terraform-docs markdown table --output-file README.md --output-mode inject infra/modules/<module>
```

Or regenerate all modules:

```bash
find infra/modules -maxdepth 3 -name main.tf -not -path '*/.terraform/*' \
  -exec sh -c 'terraform-docs markdown table --output-file README.md --output-mode inject "$(dirname "$1")"' _ {} \;
```
