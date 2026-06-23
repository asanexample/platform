# observability-pyroscope

**Continuous profiling store** (#102 P8) — Grafana **Pyroscope** v2, the profiles backend of the LGTM+**P**
stack (the **P**). Stores CPU/memory flame-graph profiles in S3, multi-tenant by `X-Scope-OrgID`, queried by
Grafana. Mirrors the Loki/Tempo/Mimir store pattern (S3 + EKS Pod Identity + per-tenant datasource).

## What it deploys

- **Pyroscope** (monolithic single-binary StatefulSet — metastore + segment-writer embedded) on S3, with a
  PVC for the local WAL + v2 metastore RAFT state.
- **S3 bucket** (SSE-S3/AES256, public-access-blocked, versioned) + **EKS Pod Identity** role (ADR-047) for
  the Pyroscope ServiceAccount — no static keys, no IRSA.
- **Multitenancy** (`multitenancy_enabled`) — `X-Scope-OrgID` required on read+write; each cluster is a tenant.
- **Grafana datasource** `Pyroscope (<tenant>)` (sidecar-discovered), one per tenant.

## Config notes

- The chart's final config = `pyroscope.config` (empty when `minio.enabled=false`) **mergeOverwrite**
  `pyroscope.structuredConfig`, so `structuredConfig` carries the whole storage + multitenancy config in
  Pyroscope's native schema.
- **SSE key** is `storage.s3.sse.type: SSE-S3` (Pyroscope's S3 config is Grafana/dskit-lineage like Mimir —
  `bucket_name` + `sse`, NOT Thanos's `bucket` + `sse_config`). Required by the org `enforce-encryption` SCP.

## Collection + correlation

Profiles are collected by the separate **Alloy eBPF** module (P8b) which `pyroscope.write`s here; the Tempo
datasource's `tracesToProfilesV2` links a span → its flame graph. A preprod profiling **spoke** (the
write-only Gateway edge, mirroring the Loki/Tempo/Mimir edges) is a follow-up.
