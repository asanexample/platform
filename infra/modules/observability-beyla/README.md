# observability-beyla (P7a)

[Grafana Beyla](https://grafana.com/oss/beyla/) — **zero-code, eBPF auto-instrumentation**. A privileged
DaemonSet that watches HTTP/gRPC/SQL traffic at the kernel level and emits **RED metrics + a service graph +
request-level traces** for **every** workload — any language, existing or new, with **no app or template
change**. This is the platform-injected instrumentation *foundation* per
[ADR-077](../../../docs/adrs/077-application-instrumentation-strategy.md); SDK-level enrichment is the opt-in
layer on top (golden-path templates, P14).

## What it does

- **Traces** → exported via OTLP to the OpenTelemetry Collector gateway (`otel-collector`, P3b) → Tempo.
- **RED + service-graph metrics** → exposed on Beyla's own Prometheus endpoint (`:9090/metrics`,
  features `application` + `application_service_graph`) and scraped by the kube-prometheus-stack Prometheus
  via a **ServiceMonitor**. This is why the Tempo **metrics-generator is not enabled** (ADR-077 D5).
- Spans/metrics are tagged with Kubernetes metadata (`attributes.kubernetes.enable`).

## Scope (dogfood)

`discovery.instrument` is scoped to the human-facing platform HTTP services
(`backstage|keycloak|argocd|observability`) so the platform cluster produces a **non-empty service graph
immediately** from real human traffic — proving APM before any tenant onboarding (P10). Broaden
`instrument_namespaces` per-tenant at P10.

## Privileges & cost

- **Privileged DaemonSet** — eBPF requires elevated kernel access (`privileged: true`); it runs in the
  already-`privileged`-PSA `observability` namespace. Treat its scope like any node-level agent.
- ~one small pod per node. `wait = false` (a DaemonSet that can't momentarily fit a packed node must not roll
  back the release — same lesson as the Alloy log DaemonSet).

## Toggle

Gated by the `enable_instrumentation` cost_profile knob (`create`). On for the platform cluster.
