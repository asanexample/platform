# Observability — Mimir (Durable Metrics Store)

Deploys **Grafana Mimir** (`mimir-distributed` chart) as the hub's durable, multi-tenant, S3-backed
long-range metrics store, into the existing `observability` namespace (so it shares Grafana's datasource
sidecar and the namespace's default-deny NetworkPolicy isolation). The hub Prometheus `remote_write`s to it;
Grafana queries it as the default datasource. Includes the **S3 blocks bucket** (SSE-S3/AES256) and an
IAM role for Mimir's ServiceAccount, bound via **EKS Pod Identity** (ADR-047). This is **P2** of the observability stack (#102).

Runs in **classic architecture** (distributor → ingester gRPC, RF1) at minimal single-replica sizing — not
the chart's default Kafka ingest-storage. `multitenancy_enabled` is on; the hub's own metrics use tenant
`platform`.

Companion docs: [current-state architecture](../../../docs/architecture/observability-current-state.md) ·
[access runbook](../../../docs/runbooks/observability-access.md) ·
[troubleshooting runbook](../../../docs/runbooks/observability-troubleshooting.md).

## Usage

```hcl
module "mimir" {
  source = "../../modules/observability-mimir"

  cluster_name = "platform-use1-eks"
  aws_region   = "us-east-1"
  namespace    = "observability" # must exist (created by the observability module)

  helm_chart_version = "6.0.6"
  high_availability  = false  # single-replica; true => RF3 + zone-aware + caches + query-scheduler x2
  storage_class      = "gp3"  # ingester/store-gateway/compactor PVCs

  default_tenant_id     = "platform"
  datasource_is_default = true # Mimir is Grafana's default datasource

  tags = local.tags
}
```

## Key inputs

| Variable | Default | Purpose |
|----------|---------|---------|
| `high_availability` | `false` | RF3, zone-aware ingester/store-gateway, multi-replica read/write, memcached caches. |
| `storage_class` | `"gp3"` | StorageClass for the ingester/store-gateway/compactor StatefulSet PVCs. |
| `force_destroy` | `true` | Allow deleting the (non-empty) blocks bucket on destroy (rebuild-safe reference platform). |
| `blocks_retention` | `"365d"` | `compactor_blocks_retention_period` (per-tenant). `0` = keep forever. |
| `default_tenant_id` | `"platform"` | `X-Scope-OrgID` for the Grafana datasource (the hub's own metrics). |
| `datasource_is_default` | `false` | Mark the provisioned Mimir Grafana datasource the default. |
| `max_global_series_per_user` / `ingestion_rate` / `ingestion_burst_size` | 1.5M / 100k / 200k | Per-tenant limits (a noisy-neighbor security control). |

## Outputs

`blocks_bucket_name`, `mimir_role_arn`, `push_endpoint`
(`http://mimir-gateway.observability.svc/api/v1/push`), `query_endpoint` (`.../prometheus`).

## Hub-only extras (ruler · app SLOs · spoke ingest)

Beyond the base store, the hub Mimir also carries (all opt-in):

- **Ruler (P4)** — `enable_ruler` turns on Mimir's ruler for server-side recording/alerting rules;
  `ruler_tenants` scopes which tenants it evaluates and `ruler_alertmanager_url` points it at the hub
  Alertmanager.
- **Per-app SLO burn-rate rules (ADR-056)** — `app_slos` renders multi-window burn-rate alerting rules
  per application into the ruler.
- **Cross-cluster `spoke_ingest` (P10)** — authenticated remote-write ingest from observability spoke
  clusters into the hub store (the P10 multi-cluster path).

## Notes / gotchas

- **Security:** `X-Scope-OrgID` is a trust header, **not** auth. In-cluster isolation rests entirely on the
  `observability` namespace NetworkPolicy (tenant `team-*` pods can't reach Mimir). Mimir is **never** exposed
  via the Cilium Gateway (ClusterIP only). Cross-cluster authenticated ingest is P10.
- **Classic, not Kafka:** the 6.0.x chart defaults to Kafka ingest-storage. This module disables it
  (`kafka.enabled=false` + `ingest_storage.enabled=false` + `ingester.push_grpc_method_enabled=true`). A
  stray `mimir-kafka` pod means the override didn't take.
- **query-scheduler is required** — the chart wires querier/query-frontend to it and has no scheduler-less
  mode; disabling it breaks the read path (DNS failures). Kept on (single replica when not HA).
- **RF1 with one ingester** — `ingester.ring.replication_factor` must be 1 or writes are rejected.
- **AES256 (SSE-S3) bucket on purpose** — keeps the Mimir role free of KMS perms (an SSE-KMS bucket needs
  `kms:GenerateDataKey*`/`Decrypt` or writes fail) and avoids per-object KMS cost. `AWS-0132` is accepted in
  `.trivyignore.yaml` (CMK is the regulated-tier upgrade). `fullnameOverride=mimir` makes service names
  deterministic (`mimir-gateway`, …); `minio.enabled=false` (we use S3); `metaMonitoring.serviceMonitor`
  on (the hub Prometheus scrapes Mimir's own metrics).
- The `mimir-gateway` (nginx) ServiceMonitor target shows as **down** (404 on `/metrics`) — benign; nginx is
  a reverse proxy with no Prometheus endpoint.
