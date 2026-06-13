# Multi-Cloud Strategy

## Overview

The platform is **multi-cloud by design but AWS-first today** — only AWS is
deployed. The strategy (shared cloud-agnostic modules, a cloud-parameterized
config hierarchy, consistent module interface contracts, and reserved
non-overlapping CIDRs per cloud) is what makes adding Azure or GCP a matter of
populating new directories rather than restructuring. This document describes that
strategy and the contracts a second cloud would implement; it does **not** describe
deployed Azure/GCP infrastructure (there is none yet).

## Design Principles

1. **Cloud-native where it matters** -- use managed services (EKS, AKS,
   Route53, Front Door) rather than abstracting to a lowest common
   denominator.
2. **Shared where possible** -- Kubernetes add-ons (CNI, GitOps, TLS,
   DNS, secrets, policy) are cloud-agnostic modules deployed via Helm.
3. **Consistent interfaces** -- networking and naming modules across all
   clouds expose a shared output contract so live configs can consume
   them uniformly.
4. **Parallel configuration** -- each cloud would have its own `_base.hcl`,
   `_versions.hcl`, and `common.hcl` following the same 6-layer
   hierarchy. Adding a new cloud means creating these files and
   populating environment directories.

## Implementation Status

Only **AWS** is deployed. Azure and GCP are **planned** — no `modules/azure`,
`modules/gcp`, `live/azure`, or `live/gcp` exists today.

| Capability | AWS | Azure / GCP |
|------------|-----|-------------|
| Config hierarchy, networking, naming patterns | Done | Planned (would reuse the shared shape) |
| Kubernetes (EKS) + Cilium (ENI) + node groups | Done | Planned (AKS/GKE + Cilium overlay) |
| IAM/Identity (IAM roles, IRSA, Pod Identity) | Done | Planned (managed identities / Workload Identity) |
| Organizations / Accounts (SCPs, Identity Center) | Done | n/a (AWS-specific) |
| ArgoCD, cert-manager, external-dns/secrets, Tailscale, gateway | Done | Planned (shared modules, reused) |
| Kyverno policy, observability (Prometheus/mimir/Grafana), Falco | Done | Planned (shared modules, reused) |
| vCluster | Deferred (ADR-033) | — |
| Live deployments | 5 accounts (mgmt, platform, test, preprod, prod) | none |

AWS is the full reference platform — EKS hub + add-ons + GitOps + VPN +
policy + observability. The shared modules and contracts below are what a
second cloud would consume.

## Module Organization

```text
infra/modules/
├── aws/                    # AWS-specific modules (eks, networking, organizations,
│   │                       #   ecr, cloudtrail, transit-gateway, iam_roles, s3, ...)
│   └── ...
├── (azure/, gcp/)          # planned — not present today
├── cloudflare/             # DNS delegation
└── (shared modules)        # Cloud-agnostic Helm / K8s deployments
    ├── cilium/  argocd/  argocd-apps/
    ├── cert-manager/  external-dns/  external-secrets/  secret-stores/
    ├── tailscale/  tailscale-admin/  gateway-config/
    ├── policy/  observability/  observability-mimir/
    ├── environment/  cluster-rbac/  eks-pod-identity/
    └── vcluster/           # deferred (ADR-033)
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

Resource names are derived from the same dimensions everywhere (there is no
standalone naming module today — names are composed inline from these locals,
surfaced by `_base.hcl`):

| Input | Type | Description |
|-------|------|-------------|
| `workload` | string | Workload identifier (e.g., `platform`) |
| `environment` | string | Environment name (e.g., `preprod`, `prod`) |
| `region_abbv` | string | Abbreviated region (e.g., `use1`) |

Names follow a consistent pattern (see [Naming Conventions](11-naming-conventions.md))
with cloud-specific accommodations for character limits and casing rules when a
second cloud is added.

### Cilium Cloud Modes

The shared `cilium` module uses `cloud_provider` to select the
appropriate networking mode:

| Cloud | Mode | Routing | Masquerade Interface |
|-------|------|---------|---------------------|
| AWS | ENI | Native routing via AWS ENI | `ens+` (AL2023 predictable names) |
| Azure | Overlay | VXLAN tunnel | Default |

## Configuration Parity

Today only `infra/live/aws/` exists. A second cloud would mirror the same
directory shape under `infra/live/{cloud}/`:

```text
infra/live/aws/            (live/{cloud}/ would mirror this)
  _base.hcl                  # composer: loads layers, merges tags, safety assertions
  _versions.hcl              # module sources + Helm pins
  common.hcl                 # cloud-wide defaults; loads secrets.hcl
  {env}/
    env.hcl                  # account ID (or subscription/project ID), env tags
    {region}/
      region.hcl  network.hcl
```

A per-cloud `_base.hcl` loads the same layers, merges tags the same way, and runs
the same safety validations — adapted for the cloud's identity model (account ID,
subscription ID, or project ID).

See [Configuration Hierarchy](../../docs/architecture/config-hierarchy.md) for the
full breakdown (and its Multi-Cloud Readiness section).

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
