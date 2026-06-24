# ADR-077: Application Instrumentation Strategy

**Status:** Accepted — Beyla eBPF baseline (P7a) + OTel Operator auto-inject (P7b) implemented + live; SDK / golden-path templates (P14) outstanding (2026-06-22)

## Context

[ADR-043](043-self-hosted-observability-stack.md) decided the observability *backbone* (kube-prometheus-stack +
the Grafana LGTM stores) and `docs/plans/102-observability-stack.md` built it out: metrics, logs, traces
(Loki/Tempo + the Alloy/OpenTelemetry-Collector tier), alerting, cloud-resource metrics, and in-cluster cost
are live (P1–P5 + P11). But several of the *remaining* phases — **P6 APM** (RED metrics + service graph),
**P9 SLOs**, **P13 per-team isolation** — turned out to have **no input**: a live check found **zero spans
flowing** through Tempo, because **nothing instruments the workloads**. The backbone is built; the on-ramp
from applications to it is not. That on-ramp is what this ADR decides.

There are two levers, and P7 ([#586](https://github.com/asanexample/platform/issues/586)) names both:
**zero-code eBPF** (Grafana Beyla) and **SDK instrumentation** (OpenTelemetry Operator auto-inject, or
hand-written SDK setup, often baked into a scaffolder template). The natural question — "should we just add
instrumentation to the Backstage software templates?" — is the decision here, because the answer sets the
contract every app and every golden-path template follows.

The platform's paved-road model is **platform-injection**: Kyverno `mutate` supplies `securityContext`, EKS
Pod Identity supplies AWS creds, and workload manifests are namespace-agnostic (the platform fills in the
environment). Telemetry should obey the same rule rather than become per-app boilerplate.

## Decision

Adopt a **layered, platform-injection-first** instrumentation strategy:

1. **Zero-code eBPF (Beyla) is the universal foundation** — RED metrics + service graph + request-level
   (HTTP/gRPC/SQL) traces for **every** workload, **any** language, existing and future, with **no app or
   template change**.
2. **The OTLP endpoint is platform-injected, never app-wired** — applications and SDKs receive
   `OTEL_EXPORTER_OTLP_ENDPOINT` (and tenant/resource attributes) from the platform, not from their own code
   or a hardcoded template value.
3. **SDK-level detail is an opt-in enrichment layer on the golden path** — new scaffolded services may add
   code-level spans/attributes via the OpenTelemetry Operator's annotation-driven auto-inject, layered *on
   top of* the Beyla baseline, never required.

This makes APM meaningful for the whole estate immediately, keeps apps free of telemetry plumbing, and means
**Backstage templates carry instrumentation support for the *richer* tier only — not as the foundation.**

## Design

### D1 — eBPF (Beyla) is the floor, not per-app SDKs

A single Beyla DaemonSet auto-discovers service traffic at the kernel level and emits RED metrics + a service
graph + request-level traces. This is chosen as the floor because it (a) covers all languages and **all
existing workloads** with zero per-app effort, and (b) is the only option consistent with platform-injection
(nothing to add to a manifest). The tradeoff — eBPF sees request boundaries, not in-process spans or custom
attributes — is acceptable for a *baseline* and is exactly what the opt-in layer (D3) fills.

### D2 — The telemetry endpoint is platform-managed config

Apps must not know the collector's address. The platform supplies the OTLP endpoint pointing at the existing
OpenTelemetry Collector (P3b) — via the OTel Operator `Instrumentation` CR and/or a namespace default /
Kyverno `mutate` of `OTEL_EXPORTER_OTLP_ENDPOINT` — exactly as it injects `securityContext` and Pod Identity.
This keeps manifests namespace-agnostic and lets the platform move the collector without touching any app.

### D3 — SDK enrichment is opt-in, delivered through the golden path

Services wanting code-level spans/attributes opt in with the OTel Operator annotation
(`instrumentation.opentelemetry.io/inject-<lang>: "true"`); the **New Product/Service scaffolder skeleton**
sets that annotation (and any minimal SDK wiring) for the chosen language. This is the *only* place templates
gain instrumentation support, and it is additive over Beyla — an un-annotated or non-template app still gets
the full Beyla baseline. (This template work is golden-path scope — P14.)

### D4 — Dogfood on the platform cluster first

Beyla deploys to the **platform** cluster before any tenant onboarding. Backstage, Grafana, Keycloak, and
ArgoCD all serve real HTTP from human use, so Beyla produces a **non-empty** service graph + RED metrics
immediately — proving the value (and the P6 APM dashboards) against real traffic before P10 brings a tenant
app in. This mirrors the plan's "dogfood on a hub workload + canary" intent.

### D5 — Beyla obviates the Tempo metrics-generator for RED/service-graph

P6's RED/service-graph metrics were to come from Tempo's metrics-generator, which derives them from *ingested
spans* — useless while nothing emits spans. Beyla produces RED metrics directly from live traffic, so we do
**not** enable the metrics-generator (saving a component). The generator remains available later if
SDK-emitted spans justify span-derived metrics; it is not the path to P6.

### D6 — Telemetry honors the data boundary and stays in-cluster

Beyla and the collector apply the same rules as [ADR-076](076-agent-observability.md): metadata freely;
request URLs/headers/payloads only under the per-compliance-tier redaction already specified for the collector
tier; secrets never; no off-cluster egress. Per-tenant attribution (`X-Scope-OrgID` / `cluster`) is stamped at
the collector, consistent with the #102 tenancy spine (P10/P13).

## Dependencies & sequencing

- **P7a — Beyla on platform (dogfood)** → **endpoint injection (D2)** → **P7b — OTel Operator + template
  opt-in (D3, with P14)**.
- Unblocks **P6** (APM now has input), **P9** (SLOs against real RED metrics), and feeds **P13** (per-team
  telemetry isolation).
- **P10** (preprod spoke) is where the first real *tenant* app (app-alpha-shop) is traced cross-cluster.
- Rides the existing collector tier (ADR-043 / #102 P3b) and the [ADR-076](076-agent-observability.md)
  content rules; no new backend.

## Consequences

- **+** APM / RED / service-graph for the entire estate with zero per-app work; existing apps covered, not
  just new ones.
- **+** Paved-road consistent — apps carry no telemetry plumbing; the endpoint is platform-managed.
- **+** Cost-efficient — one Beyla DaemonSet replaces the would-be metrics-generator; roughly net-neutral for
  far more coverage.
- **−** Beyla is a DaemonSet (per-node cost; ~3 small pods on the current cluster) and **requires elevated
  kernel privileges** (eBPF/`CAP_BPF`) — it runs in the already-`privileged`-PSA `observability` namespace,
  and its capabilities/scope must be reviewed like any node-level agent.
- **−** eBPF traces are request-level, not code-level — mitigated by the D3 opt-in SDK layer for services that
  need depth.

## Alternatives considered

- **SDK/template-baked instrumentation as the foundation** — rejected. It misses every existing app and every
  non-template workload, needs per-language template work, hardcodes the endpoint into apps (against
  platform-injection), and drifts. Retained as the *opt-in enrichment* layer (D3).
- **Tempo metrics-generator for RED, no eBPF** — rejected as the path to P6: it needs spans already flowing,
  and nothing emits them; it would be a component with no input.
- **A SaaS APM (Datadog / New Relic / Honeycomb)** — rejected; against the self-hosted, OSS-default principle
  of ADR-043. The OSS-default/commercial-opt-in seam (#102) still allows a downstream user to point OTLP
  elsewhere without re-instrumenting.

## Related

- [ADR-043](043-self-hosted-observability-stack.md) — the observability backbone this rides.
- [ADR-076](076-agent-observability.md) — agent/GenAI telemetry + the data-boundary content rules reused here.
- `docs/plans/102-observability-stack.md` — P6 (APM), P7 (auto-instrumentation), P9 (SLOs), P13 (isolation),
  P14 (golden path); issue [#586](https://github.com/asanexample/platform/issues/586).
