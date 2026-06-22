# observability-tempo

Observability **P3b (traces store)** — **Grafana Tempo** (single-binary monolith) backed by **S3**, the trace
counterpart of `observability-loki` (`docs/plans/102-observability-stack.md`). The trace **collector** (OTel) is a
separate module; apps/collector push **OTLP** here and traces are queried in Grafana.

## Key decisions

- **Monolith from `grafana-community/helm-charts`.** Grafana moved the Tempo Helm charts to the community repo
  (`https://grafana-community.github.io/helm-charts`) as of Jan 2026 — the copies in `grafana/helm-charts` are frozen.
  This is a repo move, **not** an operator pivot, and the community chart is newer (app **v2.10.7**). The **monolith**
  (one pod) fits the cost-effective cluster; **HA/prod = the `tempo-distributed` chart** (a future path).
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
