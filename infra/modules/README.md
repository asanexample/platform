# Terraform Modules

Reusable Terraform/OpenTofu modules for the platform. Cloud-agnostic modules live at the top level;
cloud-specific modules are nested under their provider directory. The platform is **AWS-only** today (Azure
and GCP modules were removed); the shared Kubernetes modules are written to be portable but are exercised
only on AWS.

## Organization

```text
modules/
├── aws/           # AWS-specific modules (19)
├── cloudflare/    # Cloudflare modules (1)
└── <shared>/      # Cloud-agnostic modules (19 — cilium, argocd, policy, observability, crossplane, …)
```

## Shared Modules (cloud-agnostic)

| Module | Description |
|--------|-------------|
| [argocd](argocd/) | ArgoCD Helm deployment with RBAC, Keycloak OIDC SSO, optional HA |
| [argocd-apps](argocd-apps/) | Multi-tenant AppProjects, Applications, PR preview ApplicationSets |
| [argocd-clusters](argocd-clusters/) | Remote cluster registration via labeled K8s Secrets |
| [cert-manager](cert-manager/) | cert-manager Helm with IRSA for DNS-01 challenges |
| [cilium](cilium/) | Cilium CNI — BYOCNI, kube-proxy replacement, Gateway API, Hubble |
| [cluster-rbac](cluster-rbac/) | platform-operator ClusterRole — least-privilege kubectl (ADR-040) |
| [crossplane](crossplane/) | Crossplane v2 control plane — hub ECR provisioning + per-cluster Environment XRD/Composition (ADR-046/048/067) |
| [external-dns](external-dns/) | ExternalDNS Helm with IRSA, Gateway API source support |
| [external-secrets](external-secrets/) | External Secrets Operator Helm with IRSA |
| [falco](falco/) | Runtime threat detection (eBPF) — module available, not yet deployed |
| [gateway-config](gateway-config/) | ClusterIssuer, Cilium Gateway, HTTPRoutes, HTTP-to-HTTPS redirect |
| [github-teams](github-teams/) | GitHub org-Team ownership of app repos, registry-derived (ADR-072) |
| [observability](observability/) | Observability hub — kube-prometheus-stack (Prometheus/Grafana/Alertmanager) + SNS alerting |
| [observability-mimir](observability-mimir/) | Durable, multi-tenant, S3-backed metrics store (Grafana Mimir) |
| [policy](policy/) | Kyverno engine + ClusterPolicies — pod hardening, multi-tenancy, image signature/attestation verification (ADR-014) |
| [secret-stores](secret-stores/) | ClusterSecretStore for Secrets Manager and SSM Parameter Store |
| [tailscale](tailscale/) | Tailscale Operator, subnet router, split DNS |
| [tailscale-admin](tailscale-admin/) | Tailnet ACL management, OAuth client provisioning |
| [actions-runner-controller](actions-runner-controller/) | Self-hosted GitHub Actions runners (ARC) — in-VPC CI for cluster-facing applies (ADR-065) |
| [vcluster](vcluster/) | vCluster Helm deployment (deferred -- see ADR-033) |

## AWS Modules

| Module | Description |
|--------|-------------|
| [cloudtrail](aws/cloudtrail/) | CloudTrail with S3 storage and KMS encryption |
| [cross-vpc-dns](aws/cross-vpc-dns/) | Cross-VPC DNS resolution for private EKS endpoints |
| [ecr](aws/ecr/) | ECR repositories with lifecycle policies and cross-account access |
| [eks](aws/eks/) | EKS cluster with BYOCNI, KMS, OIDC, access entries |
| [eks-addons](aws/eks-addons/) | EKS managed add-ons with IRSA + gp3 default StorageClass |
| [eks-node-group](aws/eks-node-group/) | EKS managed node groups |
| [eks-pod-identity](aws/eks-pod-identity/) | EKS Pod Identity associations for tenant AWS access (ADR-041) |
| [github_oidc](aws/github_oidc/) | GitHub Actions OIDC federation for keyless CI/CD (ADR-036) |
| [iam_roles](aws/iam_roles/) | Purpose-built IAM roles (PlatformAdmin, PlatformDeployer, DeveloperAccess) |
| [identity_center](aws/identity_center/) | AWS IAM Identity Center permission sets and assignments |
| [networking](aws/networking/) | VPC, subnets, NAT, flow logs, three topology modes |
| [organizations](aws/organizations/) | AWS Organizations with OUs and SCPs |
| [route53](aws/route53/) | Route53 hosted zones |
| [route53_delegation](aws/route53_delegation/) | NS record delegation between Route53 zones |
| [s3](aws/s3/) | General-purpose S3 buckets (SSE, public access blocked, ownership enforced) |
| [sns-notifications](aws/sns-notifications/) | SNS alert topic (Alertmanager → email) |
| [ssm-bastion](aws/ssm-bastion/) | SSM Session Manager bastion for private cluster access |
| [state_bootstrap](aws/state_bootstrap/) | S3 + DynamoDB backend for Terraform state |
| [transit-gateway](aws/transit-gateway/) | Transit Gateway hub/spoke for cross-VPC connectivity |

## Cloudflare Modules

| Module | Description |
|--------|-------------|
| [dns_delegation](cloudflare/dns_delegation/) | NS record delegation from Cloudflare to cloud-hosted zones |

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
