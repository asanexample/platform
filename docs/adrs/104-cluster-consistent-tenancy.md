# ADR-104: Cluster-consistent tenancy — park per-team isolation

**Date:** 2026-07-12

**Status:** Accepted — decision recorded. Implementation to follow as a separate, plan-reviewed PR (it decommissions live units; not a blind merge). Reverses the direction of P13 (#590) "per-team isolation" for now.

## Context

The observability stack currently tenants signals **inconsistently**:

| Signal | Tenant | Keyed by |
|---|---|---|
| Metrics (Mimir) | `preprod` | **cluster** |
| Traces (Tempo) | `preprod` | **cluster** |
| Logs (Loki) | `alpha` / `bravo` | **team** |

The same workload's telemetry lands in different tenants depending on the signal (logs re-tenanted per team by Alloy; metrics/traces keep the cluster tenant from the spoke edge). This was designed under P13 (#590, "designed + paused") as the first half of per-team isolation, and only logs plus a metrics dual-write shipped; traces have no per-team path at all.

Two facts make finishing it unattractive right now:

1. **No hard-isolation requirement.** There is no current compliance/customer need for teams to be unable to read each other's telemetry.
2. **OSS Grafana cannot enforce per-team reads anyway.** We run 100% OSS Grafana (no Enterprise budget). Per-datasource query permissions are an Enterprise feature; in a single OSS instance every user sees every datasource, so any user can query any tenant regardless of how the stores are split. Real per-team read isolation would additionally require Grafana Enterprise (`org_mapping` + datasource RBAC), per-team Grafana instances, or a custom tenant-injection proxy — none free, none built.

So the per-team tenant split currently delivers **zero isolation** while adding real complexity (extra units, inconsistent datasource federation, and the debugging confusion that surfaced tracing a cross-signal correlation on 2026-07-12).

## Decision

Standardize on **cluster tenancy for all three signals.** Turn off per-team tenanting (`enable_per_team_tenants = false`), so metrics, traces, and logs all key on the cluster tenant (`preprod`), and decommission the per-team machinery. Park per-team isolation behind this ADR.

### D1 — One tenant key: the cluster

All signals write and are read under the cluster's `X-Scope-OrgID`. Correlation becomes trivial: one tenant per cluster, the same key for every signal, and the `-all` federated datasources reduce to the cluster set.

### D2 — Decouple trace-context extraction from tenanting (prerequisite)

Today the Alloy `loki.process "retenant"` block does two unrelated jobs — promoting `trace_id`/`span_id` to Loki structured metadata **and** re-tenanting by team — and the whole block is gated on `per_team_tenant`. Turning the flag off naively would silently drop the structured-metadata extraction and break logs→traces. **Split them:** trace_id/span_id extraction runs unconditionally; only the `stage.tenant` + team relabel is gated. This lands first and is behavior-neutral while the flag is still on.

### D3 — Decommission the per-team components

Retire `cortex-tenant` (metrics per-team write-splitter) and the already-retired read proxies (`tenant-proxy`, `loki-tenant-proxy`, #1269). Drop `alpha`/`bravo` from the `loki` and `mimir` `extra_tenant_datasources` (and `admin_all_datasource_tenants`) so the federated datasources match the cluster-only model.

## Implementation (sequenced — apply and verify each step)

1. **Alloy module** (`observability-alloy`): move `trace_id`/`span_id` extraction + `stage.structured_metadata` out of the flag-gated `retenant` block so they always run; gate only `stage.tenant` + the team relabel. Apply, verify logs still flow and `trace_id` structured metadata is still present (logs→traces intact).
2. **`infra/live/aws/preprod/env.hcl`**: `enable_per_team_tenants = false`. This auto-flips `observability-logs-spoke.per_team_tenant`, `observability-spoke.per_team_write_url`, `mimir.cortex_tenant_route`, and `loki.spoke_ingest_passthrough`.
3. **Datasources**: `loki` and `mimir` units → `extra_tenant_datasources = ["preprod"]`; `mimir.admin_all_datasource_tenants = ["platform","preprod"]`.
4. **Decommission** `cortex-tenant`, `tenant-proxy`, `loki-tenant-proxy` units (Terraform destroy — plan-review the destroy explicitly).
5. **Verify** end-to-end after apply: metric→trace (exemplars), logs→traces, trace→logs, trace→metrics all resolve under the single cluster tenant.

## Consequences

### Positive

- One tenant key across all signals; correlation and "which tenant is my data in?" become trivial.
- Fewer moving parts (three units removed) and consistent datasource federation.
- Removes a standing source of debugging confusion.

### Negative / Known gaps

- Loses the per-team write-isolation groundwork. If a real hard-isolation need appears, it must be rebuilt — for **all** signals (traces has no path today) **and** paired with a Grafana read-enforcement decision (Enterprise / per-team instances / custom proxy).
- Historical per-team-tenant data (`alpha`/`bravo`) ages out of the stores; not migrated back to the cluster tenant.

### Risks

- The Alloy refactor (D2) touches log ingestion; must be applied and verified before the flag flip, or logs→traces regresses.
- Decommissioning is destructive; do it as a reviewed apply, not a blind merge.

## Alternatives considered

- **Complete the per-team rollout** (traces + metrics re-tenanting, per-team datasources). Rejected: large (traces needs a net-new re-tenant mechanism), no payoff without solving Grafana read-enforcement, and no current isolation requirement.
- **Leave the split and just document it** (+ fix the `tempo-all` federation gap). Rejected: keeps the cross-signal inconsistency and its debugging tax indefinitely for no benefit.

## Related

- P13 / #590 — per-team isolation (designed + paused); this ADR parks it
- #1269 — per-team read-proxy retirement (metrics + logs)
- ADR-103 — SLO materialization (also assumes the cluster tenant today)
- ADR-043 / ADR-044 — the `cluster` external label and cross-cluster tenancy
- `docs/plans/102-observability-stack.md` — P13/P14 roadmap (update to reflect this decision)
