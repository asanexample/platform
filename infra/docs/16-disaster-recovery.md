# Disaster Recovery

## Overview

The platform's recovery model today is **reproducibility from code**, not backup-and-restore: the
entire AWS estate is declared in OpenTofu/Terragrunt and can be rebuilt from the monorepo plus the
versioned remote state. Formal DR automation (cross-region replication, scheduled backups, automated
failover, signed RPO/RTO targets) is **planned, not yet implemented** — this document records the
current posture and the gaps.

> The reference platform is intentionally **rebuild-from-scratch** friendly (data buckets default
> `force_destroy = true`; `platctl teardown`/`bootstrap` tear down and recreate the whole DAG). Recovery
> is treated as "re-apply the code," which keeps the recovery path continuously exercised.

## Current Recovery Posture

### Terraform state (the critical recovery asset)

State is the one piece that cannot be regenerated from code. It is hardened in
`infra/modules/aws/state_bootstrap`:

- **S3 bucket, versioning enabled** — every state revision is retained, so a corrupted or
  accidentally-deleted state can be rolled back to a prior object version.
- **SSE encryption** + **public access blocked** on the bucket.
- **DynamoDB lock table** (`terraform-locks`) prevents concurrent-apply corruption.
- Backend config lives in `infra/root.hcl` (`bucket`, `key = <path>/terraform.tfstate`,
  `region = us-east-1`, `encrypt = true`, `dynamodb_table`, `role_arn`); the state role is
  **TerraformStateAccess** in the management account. State is keyed per unit (env/region/workload/
  module), so blast radius of any single corruption is one module.

### Infrastructure

Every module and environment is code. A lost cluster, VPC, or account-level resource is recovered by
re-running the apply for that unit (or `terragrunt run --all apply` / `platctl bootstrap` for a whole
environment), honoring the documented [deployment ordering](../../CLAUDE.md#deployment-ordering-aws).
Module sources are pinned via `_versions.hcl`, so a rebuild reproduces the exact code that was live.

### Application workloads

Standard-tier environments are **stateless** containers pulled from ECR and reconciled by **ArgoCD** from
Git — recovery is "point ArgoCD at the repo and sync." Container images live in per-team ECR repos
(immutable tags, scan-on-push). There is **no environment database tier** in the current `standard`
clusters, so there is no application data to back up yet.

### Secrets

Secrets of record live in **AWS Secrets Manager** (per-account); External Secrets Operator re-syncs
them into a rebuilt cluster automatically. Losing a cluster does not lose secrets.

### Cluster rebuild runbook

The end-to-end "rebuild a cluster after teardown" procedure (including re-establishing Tailscale
access) is in the
[Tailscale VPN runbook](../../docs/runbooks/tailscale-vpn.md#rebuilding-after-teardown).

## Gaps / Planned

These are **not** implemented today and are the roadmap for a formal DR program:

| Capability | Status | Notes |
|------------|--------|-------|
| Cross-region state replication | Planned | S3 CRR of the state bucket to a second region |
| Scheduled state backups | Partial | versioning covers rollback; no separate off-account copy yet |
| Stateful-workload backup (Velero / EBS snapshots) | Planned | needed once an environment data tier (RDS/PVC) lands |
| Multi-region / multi-AZ failover | Planned | clusters are single-region today |
| RPO/RTO targets per tier | Planned | to be defined with the HIPAA/PCI tiers |
| DR game-days / restore testing | Planned | teardown/bootstrap exercises rebuild, but not a formal drill |

When stateful regulated-tier workloads (hipaa/pci) land, this document will be expanded with
RPO/RTO targets, automated backup/restore procedures, and failover runbooks.

## Next Steps

Continue to [Available Modules](17-available-modules.md) to understand the reusable infrastructure
components available in the Reference Platform.
