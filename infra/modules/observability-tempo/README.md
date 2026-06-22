# observability-tempo

Observability **P3b (traces store)** — **Grafana Tempo** (`tempo-distributed`) backed by **S3**, the trace
counterpart of `observability-loki` (`docs/plans/102-observability-stack.md`). The trace **collector** (OTel) is a
separate module; apps/collector push **OTLP** here and traces are queried in Grafana.

## Key decisions

- **One chart sized by `high_availability`** (same spirit as Loki's SingleBinary↔SimpleScalable toggle): dev runs
  every component at 1 replica / RF1 / caches off (~5 small pods), so **dev exercises the real prod architecture
  scaled down**; HA flips to RF3 + zone-aware + multi-replica + caches. The single-binary monolith can't do HA, so
  using the distributed chart for both keeps the `cost_profile` switch coherent for Tempo.
- **From `grafana-community/helm-charts`.** Grafana moved the Tempo Helm charts there (Jan 2026) and froze the
  `grafana/helm-charts` copies — a repo move, **not** an operator pivot; the community chart is newer (app **v2.10.7**).
- **S3 + EKS Pod Identity (ADR-047)** — same shape as Loki: SSE-S3 bucket, a role trusting `pods.eks.amazonaws.com`
  bound to the Tempo ServiceAccount; **no IRSA annotation**. The S3 client sends `x-amz-server-side-encryption`
  (`storage.trace.s3.sse=SSE-S3`) to satisfy the org `enforce-encryption` SCP (the same fix Loki needed).
- **OTLP receivers only** (gRPC 4317 / HTTP 4318); jaeger/opencensus dropped. Query API on **3200**.
- **Trace→logs correlation**: the Grafana Tempo datasource (`uid=tempo`) `tracesToLogsV2` → the Loki datasource,
  pairing with Loki's `trace_id` derivedField (→ `tempo`) for bidirectional jumps.
- **metrics-generator off** (service graphs / span metrics need Prometheus remote-write; defer with Mimir).
- Gated by **`enable_tempo`** (cost_profile per-knob override). Trace retention via `tempo.retention` (dev: 72h).

## Verify

After apply: `kubectl -n observability get pods -l app.kubernetes.io/name=tempo` (1/1 Running), check the pod logs
have no S3 `AccessDenied` (Pod Identity + SSE OK), and the **Tempo** datasource appears in Grafana. End-to-end trace
flow is proven once the OTel collector ships and emits a test span.
