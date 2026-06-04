# ADR-054: Platform Resilience & Business Continuity

**Date:** 2026-06-04

**Status:** Proposed — **strategy/direction.** Realizes the per-tier **recovery** and **availability** postures
reserved in [ADR-049](049-tenant-model-team-tenant-zone.md) /
[tenant-api-v2.md](../architecture/tenant-api-v2.md#tier-profiles--isolation--recovery--availability). Builds on
[ADR-002](002-aws-state-storage.md) (state backend), [ADR-006](006-state-bootstrap-pattern.md),
[ADR-037](037-cloudtrail-audit-logging.md), and the observability stack ([ADR-043](043-self-hosted-observability-stack.md)/[ADR-044](044-mimir-durable-multi-tenant-metrics.md)).

## Context

The tenant model now *references* a recovery posture (RPO/RTO/retention) and an availability target per tier,
but **nothing realizes them**. Two concrete exposures:

- **Stateful data has no backup story.** The "rebuild = destroy/recreate from IaC" ethos covers *stateless*
  infra, but not the data that can't be re-derived: tenant data, the Keycloak and Backstage CloudNativePG
  databases, and the Terraform **state backend** itself. A region or account loss today is data loss.
- **The platform control plane is single-region (us-east-1).** ArgoCD, Crossplane, Keycloak, Backstage, the
  observability hub, and the S3/DynamoDB state backend all live in one region — an undocumented single point of
  failure with no tested recovery path. Regulated and customer-isolated tenants contractually require *tested*
  recovery, not best-effort.

## Decision

1. **Backup mechanisms realize the tier recovery posture.** Each tier's RPO/RTO/retention
   (tenant-api-v2) maps to concrete mechanisms: **CloudNativePG** continuous backup + PITR to S3 for all
   Postgres (Backstage, Keycloak, tenant `relational` data-services); **Velero** for cluster/namespace state +
   PVs; **AWS Backup** for account-level resources. Regulated **retention holds** (e.g. 7y PCI) are enforced
   with S3 Object Lock / lifecycle, shared with the compliance-evidence store ([ADR-055](055-compliance-assurance-and-continuous-control-evidence.md)).
2. **The state backend is itself DR-protected** — S3 state bucket versioning + **cross-region replication**,
   DynamoDB lock table PITR. The platform cannot self-recover if the thing that holds its own state is
   single-region.
3. **Control-plane region posture: single-region with a documented, *tested* recovery plan; active-active
   multi-region deferred behind explicit triggers.** Because the control plane is reconstructable from Git +
   IaC (ArgoCD/Crossplane/Terragrunt) and its only true state is the backed-up DBs + state backend, recovery
   from a region loss = re-bootstrap in a secondary region + restore from cross-region backups — an **RTO of
   hours, captured as a runbook and exercised by a periodic DR drill** (an untested backup is not DR).
   Active-active is deferred; **triggers to revisit:** a contractual platform-availability SLA single-region
   can't meet, or prod tenants whose availability tier exceeds the single-region ceiling.
4. **The tier availability target is the platform's SLO contract; error budgets govern change velocity.** The
   per-tier availability posture (tenant-api-v2) *is* the SLO the platform commits to; the observability stack
   ([#102](https://github.com/asanexample/platform/issues/102)) measures it, and **budget exhaustion freezes
   non-critical rollouts** (cross-ref [ADR-056](056-progressive-delivery-and-safe-rollback.md)). A tenant's
   availability cannot exceed the platform region ceiling — already stated in the schema, made an explicit
   commitment here.

## Alternatives considered

- **Active-active multi-region control plane now.** Strongest, but the cost/complexity is unjustified
  pre-demand and the control plane is reconstructable — restore-from-backup meets the current bar. Rejected as
  premature; kept behind triggers.
- **Backup-by-rebuild only** (lean on IaC, no data backup). Loses every stateful component. Rejected.
- **Per-tenant DR as an opt-in toggle.** Folded into the tier instead — DR posture is a *property of the
  hardening level*, not a per-tenant switch.

## Consequences

- Realizes the reserved recovery/availability postures; makes "what's our RTO for a prod-pci tenant?" answerable
  from the model.
- **DR drills become mandatory** — the plan is only real once exercised; this is recurring ops cost.
- Keycloak / Backstage / CloudNativePG are confirmed **Tier-0** with backup + restore discipline.
- Secondary-region prerequisites (replicated state, ECR image availability, AMIs) must exist *before* an
  incident, not during.
- Cost: cross-region replication + backup storage + retention-locked evidence storage.
- **Open:** the DR-drill cadence, the secondary-region choice, and the boundary between Velero and AWS Backup.
