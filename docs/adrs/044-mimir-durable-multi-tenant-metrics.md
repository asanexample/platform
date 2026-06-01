# ADR-044: Grafana Mimir for Durable, Multi-Tenant Metrics Storage

**Date:** 2026-05-31

**Status:** Accepted — P2 implemented + live on the platform cluster. Extends
[ADR-043](043-self-hosted-observability-stack.md) (the observability stack) with the durable store.
As-built in [observability-current-state](../architecture/observability-current-state.md).

## Context

[ADR-043](043-self-hosted-observability-stack.md) stands up Prometheus + Grafana, but Prometheus's local
TSDB is the wrong long-term store for this platform:

- **Not durable** — local PVC/emptyDir; losing the pod or node loses history. Long retention means large,
  single-node EBS volumes (a scaling ceiling and a cost).
- **Not multi-tenant** — Prometheus has no tenant model. The hub-and-spoke design needs **per-tenant**
  isolation: each spoke cluster (preprod/prod) and, eventually, each team must write/read its own metrics
  without seeing others'.
- **Not multi-cluster** — there's no native way to fan in remote-writes from spokes and query them as one.

We need a durable, horizontally-scalable, **multi-tenant** metrics store on cheap object storage that
Prometheus can `remote_write` to additively (no migration), and that Grafana queries as one backend.

### Alternatives considered

**1. Grafana Mimir (chosen).** Grafana Labs' actively-developed fork of Cortex. **Native multi-tenancy**
via the `X-Scope-OrgID` header (the tenancy spine the spokes/teams need), S3 object storage, horizontal
scaling, Prometheus-`remote_write` + PromQL compatible, Grafana-native, single-binary→microservices path,
OSS.

**2. Thanos (rejected/close).** Also OSS, also object-store-backed, mature. But its model is a
**sidecar per Prometheus** + store-gateway + querier federation — more moving parts to glue for a hub, and
multi-tenancy is bolted on (per-tenant via external labels / receive) rather than first-class. Mimir's
`X-Scope-OrgID` tenancy and single horizontally-scaled ingest path fit the hub-and-spoke + per-team goal more
directly. Defensible either way; we optimized for native tenancy + a clean scale path.

**3. Cortex (rejected).** Mimir *is* the Grafana fork of Cortex and is where the development happens;
choosing Cortex would be choosing the less-maintained upstream.

**4. Amazon Managed Prometheus / AMP (rejected, consistent with ADR-043).** Per-sample ingest + per-query
billing; tenancy is per-workspace (coarser, AWS-IAM-shaped) rather than `X-Scope-OrgID`; AWS-only / not
portable. Revisit with the `metrics_backend` seam if ops burden dominates.

**5. Just give Prometheus bigger PVCs + longer retention (rejected).** Doesn't address multi-tenancy or
multi-cluster, keeps the single-node ceiling, and EBS is a pricier, less durable tier than S3.

## Decision

Run **Grafana Mimir** (`mimir-distributed` chart 6.0.6, app 3.0.x) as the durable, multi-tenant metrics
store, in the same `observability` namespace. The hub Prometheus `remote_write`s every sample to it; Grafana's
**default datasource is Mimir** (full history), with Prometheus kept selectable for recent/local queries.
The hub's own metrics use tenant `platform`; spokes will write under their own tenants (P10).

Load-bearing choices:

- **`multitenancy_enabled` + `X-Scope-OrgID`** as the tenancy spine. **Critical caveat:** the header is a
  *trust header, not authentication* — Mimir doesn't verify it. **In-cluster isolation rests entirely on the
  NetworkPolicy:** the `observability` namespace is default-deny ingress + allow-intra-namespace, so tenant
  (`team-*`) and other namespaces **cannot reach Mimir at all**, and Mimir is **never** exposed via the
  Cilium Gateway (ClusterIP only). Cross-cluster ingest from spokes must be authenticated + the header
  overwritten at the hub edge (P10).
- **S3 object storage** for blocks, **SSE-S3 (AES256)** specifically so the Mimir IRSA needs no KMS perms
  (an SSE-KMS bucket would require `kms:GenerateDataKey*`/`Decrypt` or writes fail) and to avoid per-object
  KMS cost on a high-churn store.
- **Classic architecture** (distributor→ingester gRPC, RF1), *not* the chart-default Kafka ingest-storage —
  lighter for the reference cluster; ingester/store-gateway/compactor on gp3 PVCs (local working set only).
- **Per-tenant limits** (series/ingestion caps) double as the noisy-neighbor security control.
- `high_availability` toggle scales to RF3 + zone-aware + caches when a cluster has the capacity.

## Consequences

### Positive

- **Durable, long-range history on cheap S3** — Prometheus can be lost/rebuilt without losing data.
- **The multi-tenant spine** — `X-Scope-OrgID` is the foundation for onboarding preprod/prod spokes and,
  later, per-team isolation (P10/P13) — the reason Mimir was chosen over a single-tenant store.
- **Additive, no migration** — Prometheus stays the scraper + short buffer and remote-writes; Grafana just
  gains a default datasource.
- **Horizontally scalable + OSS-portable** — the single-binary→microservices path; no vendor lock-in.

### Negative

- **The trust-header model demands NetworkPolicy discipline** — isolation is *only* as good as the network
  boundary; a misconfigured policy or an exposed gateway would let any caller read/write any tenant. This is
  the single most important operational invariant.
- **Operational complexity** — even minimal classic mode is ~7–8 components (gateway, distributor, ingester,
  querier, query-frontend, query-scheduler, store-gateway, compactor). The query-scheduler is **required**
  (the chart wires querier→scheduler); RF must match replica count; the in-place emptyDir→PVC + helm/operator
  recreation gotchas apply (see the troubleshooting runbook).
- **Cross-cluster auth deferred** — P2 is single-cluster; authenticated spoke ingest with header overwrite is
  P10 and is a prerequisite before any spoke writes to the hub.
- **More cost surface** — extra pods + S3 + gp3 PVCs; modest on a reference cluster, real at scale (S3
  lifecycle tiering is a later cost lever).
