# observability-otel-collector

Observability **P3b (trace pipeline)** — an **OpenTelemetry Collector** (deployment-mode gateway) that receives
**OTLP** from applications and forwards it to **Tempo**, completing P3b (`docs/plans/102-observability-stack.md`).
This is the trace counterpart of the Alloy log pipeline; the traces store is `observability-tempo`.

## Key decisions

- **Deployment-mode gateway** (not a DaemonSet): apps point at this collector's Service; it batches and exports to
  the Tempo distributor. A central gateway decouples apps from the backend and is the standard trace-ingest shape.
- **`otelcol-k8s` distro** (`image: otel/opentelemetry-collector-k8s`) — carries the otlp receiver/exporter,
  `batch`, and `memory_limiter`. **No AWS identity** — the collector only forwards in-cluster to Tempo (never
  touches S3), so no Pod Identity and the encryption SCP doesn't apply.
- **Pipeline**: `otlp → memory_limiter → batch → otlp/tempo` (`tls.insecure` — in-cluster plaintext). We override
  only the traces pipeline + add the Tempo exporter; the chart's default otlp receiver + batch are reused.
- Sized by **`high_availability`** (1 replica dev / 2 prod). Gated by **`enable_trace_pipeline`** (cost_profile
  per-knob override); the Tempo OTLP endpoint comes from the `observability-tempo` module.
- **Follow-ups**: `k8sattributes` enrichment (pod/namespace span tags + RBAC) and tail-sampling.

## Verify

After apply: `kubectl -n observability get deploy otel-collector` (Ready), then send a synthetic trace to
`otel-collector.observability.svc:4318` (e.g. `telemetrygen traces` or an OTLP curl) and query it in Grafana →
Explore → Tempo. Trace→logs correlation is wired on the Tempo datasource (→ Loki).
