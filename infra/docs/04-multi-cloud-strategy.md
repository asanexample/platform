# Multi-Cloud Strategy

## Overview

The platform supports AWS, Azure, and GCP with a shared configuration
framework and consistent module interfaces. Cloud-specific modules use
native services (EKS, AKS, VPCs, VNets); shared modules (Cilium,
ArgoCD, cert-manager) deploy identically on any cluster.

## Design Principles

1. **Cloud-native where it matters** -- use managed services (EKS, AKS,
   Route53, Front Door) rather than abstracting to a lowest common
   denominator.
2. **Shared where possible** -- Kubernetes add-ons (CNI, GitOps, TLS,
   DNS, secrets, policy) are cloud-agnostic modules deployed via Helm.
3. **Consistent interfaces** -- networking and naming modules across all
   clouds expose a shared output contract so live configs can consume
   them uniformly.
4. **Parallel configuration** -- each cloud has its own `_base.hcl`,
   `_versions.hcl`, and `common.hcl` following the same 7-layer
   hierarchy. Adding a new cloud means creating these three files and
   populating environment directories.

## Implementation Status

| Feature | AWS | Azure | GCP |
|---------|-----|-------|-----|
| Config hierarchy (`_base.hcl`, `_versions.hcl`, `common.hcl`) | Done | Done | Done |
| Naming module | Done | Done | Done |
| Networking module | Done | Done | Done |
| Kubernetes (EKS / AKS) | Done | Done | -- |
| Cilium CNI | Done (ENI mode) | Done (overlay) | -- |
| Node groups / pools | Done | Done | -- |
| IAM / Identity | Done (IAM roles, IRSA) | Done (managed identities, federated creds) | -- |
| Organizations / Accounts | Done (Organizations, SCPs, Identity Center) | -- | -- |
| ArgoCD | Done | -- | -- |
| cert-manager | Done | -- | -- |
| external-dns | Done | -- | -- |
| external-secrets | Done | -- | -- |
| Tailscale VPN | Done | -- | -- |
| Gateway ingress | Done | -- | -- |
| Storage | -- | Done | -- |
| Container registry | -- | Done | -- |
| Observability (Grafana, Prometheus) | -- | Done | -- |
| Front Door / CDN | -- | Done | -- |
| Key Vault / KMS | Secrets encryption via EKS KMS | Done | -- |
| Policy (Kyverno) | Available | Available | Available |
| vCluster | Available | Available | Available |
| Live deployments | 5 accounts (mgmt, platform, test, preprod, prod) | 2 subscriptions (dev, ops) | Scaffolded (ops) |

AWS and Azure are both production-capable with different strengths: AWS
has the full Kubernetes platform stack (EKS + add-ons + VPN + GitOps);
Azure has the full application infrastructure stack (AKS + observability +
CDN + storage).

## Module Organization

```text
infra/modules/
├── aws/                    # 12 AWS-specific modules
│   ├── eks/
│   ├── networking/
│   ├── organizations/
│   └── ...
├── azure/                  # 24 Azure-specific modules
│   ├── aks_core/
│   ├── networking/
│   ├── frontdoor_profile/
│   └── ...
├── gcp/                    # 2 GCP-specific modules
│   ├── naming/
│   └── networking/
├── cloudflare/             # DNS delegation
└── (shared modules)        # Cloud-agnostic Helm deployments
    ├── cilium/
    ├── argocd/
    ├── cert-manager/
    ├── external-dns/
    ├── external-secrets/
    ├── tailscale/
    ├── tailscale-admin/
    ├── gateway-config/
    ├── policy/
    └── vcluster/
```

### Cloud-Specific vs Shared

**Cloud-specific modules** create cloud-native resources: VPCs, AKS
clusters, IAM roles, storage accounts. They use the corresponding cloud
provider (AWS, AzureRM, Google).

**Shared modules** deploy Helm charts or Kubernetes manifests. They
accept credentials and identity primitives as variables -- the live unit
handles sourcing them from cloud-specific stores. For example, the
`cilium` module accepts a `cloud_provider` variable that switches
between ENI mode (AWS) and overlay mode (Azure).

## Cross-Cloud Interface Contracts

### Networking Outputs

All networking modules expose a shared output set:

| Output | AWS | Azure | GCP |
|--------|-----|-------|-----|
| `network_id` | VPC ID | VNet ID | VPC Network ID |
| `network_name` | VPC name | VNet name | VPC Network name |
| `subnet_ids` | Map of names to IDs | Map of names to IDs | Map of names to IDs |
| `kubernetes_subnet_id` | First EKS subnet | AKS subnet | GKE subnet |
| `create` | Whether resources created | Whether resources created | Whether resources created |

Each cloud also exposes cloud-specific outputs (e.g., AWS:
`vpc_cidr_block`, `nat_gateway_ids`; GCP: `vpc_self_link`,
`cloud_nat_id`).

### Naming Contract

All naming modules (`aws/naming`, `azure/naming`, `gcp/naming`) accept
the same inputs:

| Input | Type | Description |
|-------|------|-------------|
| `workload` | string | Workload identifier (e.g., `platform`) |
| `environment` | string | Environment name (e.g., `dev`, `prod`) |
| `region_abbv` | string | Abbreviated region (e.g., `use1`, `eus`, `usc1`) |

Names follow the CAF-aligned pattern `{type}-{workload}-{env}-{region}`
with cloud-specific accommodations for character limits and casing rules.

### Cilium Cloud Modes

The shared `cilium` module uses `cloud_provider` to select the
appropriate networking mode:

| Cloud | Mode | Routing | Masquerade Interface |
|-------|------|---------|---------------------|
| AWS | ENI | Native routing via AWS ENI | `ens+` (AL2023 predictable names) |
| Azure | Overlay | VXLAN tunnel | Default |

## Configuration Parity

Each cloud has a parallel directory structure:

```text
infra/live/
  aws/                    azure/                  gcp/
    _base.hcl               _base.hcl               _base.hcl
    _versions.hcl           _versions.hcl           (not yet)
    common.hcl              common.hcl              common.hcl
    {env}/                  {env}/                  {env}/
      env.hcl                 common.hcl              env.hcl
      {region}/               {region}/               {region}/
        region.hcl              region.hcl              region.hcl
        network.hcl             network.hcl             network.hcl
```

The `_base.hcl` in each cloud loads the same layers, merges tags the
same way, and runs the same safety validations -- adapted for the
cloud's identity model (account ID, subscription ID, or project ID).

See
[Configuration Hierarchy](../../docs/architecture/config-hierarchy.md#azure-vs-aws-parallel-structure-comparison)
for a detailed side-by-side comparison.

## Adding a New Cloud

1. Create `infra/live/{cloud}/_base.hcl` following the existing pattern
   (load common, env, region, network, workload; merge tags; safety
   assertions using the cloud's identity type).
2. Create `infra/live/{cloud}/_versions.hcl` with module source paths.
3. Create `infra/live/{cloud}/common.hcl` with project tags and the
   environment-to-identity safety map.
4. Create cloud-specific modules under `infra/modules/{cloud}/`.
5. Populate environment, region, and workload directories.

## Next Steps

Continue to [Environment Management](05-environment-management.md) to
understand how environments are isolated and managed across clouds.
