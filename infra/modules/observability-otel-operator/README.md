# observability-otel-operator (P7b)

The [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator) + a platform
`Instrumentation` CR — the **opt-in, SDK-level enrichment layer** on top of Beyla's zero-code baseline
([ADR-077](../../../docs/adrs/077-application-instrumentation-strategy.md) D2/D3).

## What it does

- **Operator** (chart `opentelemetry-operator`): a controller + mutating webhook that injects a language SDK
  (Java / Python / Node.js / .NET / Go) as an init container into pods carrying the inject annotation. The
  webhook serving cert comes from **cert-manager**. Installs the `Instrumentation` (and
  `OpenTelemetryCollector`) CRDs.
- **Platform `Instrumentation` CR** (`<namespace>/<instrumentation_name>`, default `observability/platform`):
  holds the **platform-injected OTLP endpoint** (→ the OpenTelemetry Collector gateway, P3b) + propagators +
  sampler. Apps never hardcode the endpoint (ADR-077 D2). Delivered as a **local Helm chart** (not
  `kubernetes_manifest`) so the CR can reference the operator's CRD from the same apply — the crossplane-module
  convention.

## How apps opt in

A workload adds an annotation (this is the golden-path/scaffolder's job — P14, **not** the platform baseline):

```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-java: "observability/platform"   # or inject-python / -nodejs / -dotnet / -go
```

The operator then injects the SDK + `OTEL_EXPORTER_OTLP_ENDPOINT` from the CR. This adds **code-level spans +
custom attributes** on top of Beyla's request-level RED/traces — it is additive, never required.

## Scope & toggle

This deploys the **mechanism + the platform endpoint**. Active SDK injection begins when a workload opts in
(a tenant app at P10, or via the scaffolder at P14). Gated by the `enable_instrumentation` cost_profile knob
(shared with the Beyla unit). The operator is ~one small pod.
