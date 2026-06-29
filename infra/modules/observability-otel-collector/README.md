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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.otel_collector](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_exporter_tls_insecure"></a> [exporter\_tls\_insecure](#input\_exporter\_tls\_insecure) | TLS for the trace exporter. true = plaintext (in-cluster hub→Tempo). false = verify TLS (spoke→edge, public Let's Encrypt cert). | `bool` | `true` | no |
| <a name="input_exporter_use_http"></a> [exporter\_use\_http](#input\_exporter\_use\_http) | false = OTLP/gRPC exporter to an in-cluster Tempo distributor (hub). true = OTLP/HTTP exporter to the hub Tempo edge over the Gateway (spoke), since the HTTPRoute terminates HTTP. | `bool` | `false` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Helm chart name. | `string` | `"opentelemetry-collector"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | opentelemetry-collector chart version (pinned in \_versions.hcl; latest stable at authoring). | `string` | `"0.158.2"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name (also fullnameOverride, the Service name, and the ServiceAccount name). | `string` | `"otel-collector"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Helm repository URL. | `string` | `"https://open-telemetry.github.io/opentelemetry-helm-charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm operation timeout (seconds). | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready. | `bool` | `true` | no |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | Sizing toggle (cost\_profile). false = 1 replica (dev). true = 2 replicas (gateway HA). | `bool` | `false` | no |
| <a name="input_mimir_endpoint"></a> [mimir\_endpoint](#input\_mimir\_endpoint) | Mimir Prometheus remote\_write URL (e.g. the mimir module's push\_endpoint, http://…-gateway…/api/v1/push). When set, the collector adds an OTLP→Mimir metrics pipeline; empty leaves it traces-only. | `string` | `""` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy the collector into. Must already exist (created by the observability module). | `string` | `"observability"` | no |
| <a name="input_resource_attributes"></a> [resource\_attributes](#input\_resource\_attributes) | Resource attributes upserted on every span via a `resource` processor — e.g. { cluster = "preprod" } on a spoke so the hub can isolate/break-out traces by cluster (#628). Empty = no resource processor. | `map(string)` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags (the collector creates no AWS resources; informational). | `map(string)` | `{}` | no |
| <a name="input_tempo_otlp_endpoint"></a> [tempo\_otlp\_endpoint](#input\_tempo\_otlp\_endpoint) | Where the collector exports traces. HUB (gRPC): the in-cluster Tempo distributor `host:port` (no scheme). SPOKE (HTTP): the hub Tempo edge base URL `https://<spoke>-traces.<domain>` (the otlphttp exporter appends /v1/traces). Driven by exporter\_use\_http. | `string` | `"tempo-distributor.observability.svc:4317"` | no |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Tenant (X-Scope-OrgID) stamped on the exported traces (Tempo multitenancy, #628). Hub = `platform`. For a spoke it's belt-and-suspenders — the hub Gateway edge force-overwrites it per-hostname. | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_otlp_grpc_endpoint"></a> [otlp\_grpc\_endpoint](#output\_otlp\_grpc\_endpoint) | OTLP/gRPC endpoint apps send traces to (this collector's service). |
| <a name="output_otlp_http_endpoint"></a> [otlp\_http\_endpoint](#output\_otlp\_http\_endpoint) | OTLP/HTTP endpoint apps send traces to. |
<!-- END_TF_DOCS -->