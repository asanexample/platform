# Cost Management Strategy

## Overview

Cost control on the platform is mostly **structural** — the architecture bakes in
cheaper defaults — plus **tag-based allocation** for visibility. Active cost *monitoring*
(budgets, anomaly alerts) is largely **planned**; this page documents what's in place and
what's next. AWS is the only deployed cloud; the same patterns extend to Azure/GCP.

## Cost allocation via tags

Every resource carries the standard tag set (see [Tagging Strategy](12-tagging-strategy.md)),
merged through `_base.hcl`. The cost-relevant keys:

| Tag | Use |
|-----|-----|
| `Environment` | Per-env spend (platform / preprod / prod) |
| `Team` / `Workload` | Per-tenant / per-workload attribution (basis for showback) |
| `CostCenter` | Accounting group |
| `ComplianceTier` | Spend by tier (regulated tiers cost more) |

Each environment is also a **separate AWS account** (5 accounts), so account-level billing
already isolates spend before tags. Activate these as **cost allocation tags** in the
management account to break them out in Cost Explorer.

## Structural cost levers (in place)

| Lever | Where | Saving |
|-------|-------|--------|
| **Single NAT gateway** for non-prod | `single_nat_gateway = true` (networking unit) | ~$32/mo × (AZs−1) per VPC |
| **S3 gateway endpoints** on every VPC | networking module (free) | Keeps S3 traffic off the NAT data path |
| **Private-only EKS + internal NLB** | no public ALBs; ingress via Tailscale | Avoids public LB + data-egress |
| **Scale-to-zero off-hours** | node groups `desired=0` overnight | Nodes are the largest line item |
| **Small nodes** (`t3.large`) | node-group units | Right-sized for current load |
| **gp3 EBS** | launch template + StorageClass | Cheaper/faster than gp2 |
| **Custom PHZ cross-VPC DNS** | `dns_method` (not Resolver endpoints) | ~$365/mo avoided vs resolver endpoints |
| **SSE-S3 (not KMS) on high-churn buckets** | Mimir/data buckets | No per-object KMS request cost |
| **Cilium overlay** | `cluster-pool` IPAM | Pods don't consume VPC IPs → no secondary-CIDR/larger-subnet cost |

## Major cost drivers (what to watch)

- **EC2 worker nodes** — the dominant cost; managed by node-group sizing + scale-to-zero.
- **EKS control plane** — ~$0.10/hr per cluster (platform + preprod).
- **NAT gateways** — hourly + per-GB; single-NAT for non-prod, S3 endpoint offload.
- **Transit Gateway** — per-attachment hourly + per-GB processed (hub + spokes).
- **EBS + S3** — node volumes, Mimir/observability object storage, state bucket.
- **Data transfer** — cross-AZ and egress; minimized by keeping traffic in-VPC/in-region.

## Environment-specific optimization

- **preprod / non-prod** — single NAT, scale-to-zero off-hours, minimal node counts, no
  multi-AZ NAT redundancy.
- **platform (hub)** — runs shared services (ArgoCD, observability, TGW hub); sized for
  per-AZ coverage (system `desired=3`) which is a deliberate availability-over-cost call.
- **prod** — networking + org scaffolding only today (no cluster), so near-zero compute cost.

## Monitoring & governance (planned)

- **AWS Budgets** + SNS alerts per account/tag — *not yet implemented* (no `aws_budgets`
  resources in the IaC).
- **Cost Anomaly Detection** and scheduled **Cost Explorer** reports.
- **Right-sizing** from observability (the Prometheus/Mimir stack already collects node/pod
  utilization — feed it into sizing decisions).
- **Savings Plans / Reserved Instances** once steady-state usage is established (currently
  all On-Demand; note the account's low On-Demand vCPU quota also bounds scale — see #168).

## Next Steps

Continue to [Region Scaffolding](20-region-scaffolding.md).
