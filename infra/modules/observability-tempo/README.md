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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.tempo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.tempo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.tempo_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.traces](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.traces](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.traces](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_public_access_block.traces](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.traces](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.traces](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [helm_release.tempo](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map_v1.grafana_datasource](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_manifest.spoke_ingest_from_gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.spoke_ingest_route](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [aws_iam_policy_document.tempo_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name (Pod Identity association + S3 bucket name prefix). | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region (S3 bucket + the Tempo S3 endpoint). | `string` | `"us-east-1"` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_default_tenant_id"></a> [default\_tenant\_id](#input\_default\_tenant\_id) | Tenant (X-Scope-OrgID) the default Tempo datasource queries with, and that the hub's own traces are written under. | `string` | `"platform"` | no |
| <a name="input_enable_federated_datasource"></a> [enable\_federated\_datasource](#input\_enable\_federated\_datasource) | Provision a `Tempo (all clusters)` datasource querying ALL tenants at once (`X-Scope-OrgID: <default>|<extras…>`). Tempo supports multi-tenant queries via the pipe-separated header. Platform-admin overview lane (#629). Off by default. | `bool` | `false` | no |
| <a name="input_enable_metrics_generator"></a> [enable\_metrics\_generator](#input\_enable\_metrics\_generator) | Enable the Tempo metrics-generator (P6 / APM): derives RED span-metrics + a service graph from traces and remote\_writes them to Mimir, per-tenant (X-Scope-OrgID preserved). Needs Mimir on. Off = no APM metrics. | `bool` | `false` | no |
| <a name="input_enable_traces_to_profiles"></a> [enable\_traces\_to\_profiles](#input\_enable\_traces\_to\_profiles) | Add the `tracesToProfilesV2` link to each Tempo datasource (P8b) — a span jumps to its CPU flame graph in the matching Pyroscope tenant datasource (`tempo`->`pyroscope`). Set when Pyroscope (the profiles store) is deployed. | `bool` | `false` | no |
| <a name="input_extra_tenant_datasources"></a> [extra\_tenant\_datasources](#input\_extra\_tenant\_datasources) | Additional X-Scope-OrgID tenants to provision as Grafana datasources — e.g. ["preprod"] for the preprod traces spoke (#628). Each renders a `Tempo (<tenant>)` datasource. | `list(string)` | `[]` | no |
| <a name="input_federated_profiles_cluster"></a> [federated\_profiles\_cluster](#input\_federated\_profiles\_cluster) | Which cluster's Pyroscope datasource the FEDERATED `tempo-all` datasource links profiles to. Pyroscope has no federated `-all` datasource (unlike Mimir/Tempo), so the all-clusters trace view must point at one cluster's profiles store — the spoke that runs the instrumented apps. Yields `pyroscope-<value>`. | `string` | `"preprod"` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Allow deleting the (non-empty) traces bucket on destroy. Dev convenience. | `bool` | `false` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Helm chart name — tempo-distributed (one chart, sized by high\_availability). | `string` | `"tempo-distributed"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | grafana-community/tempo-distributed chart version (pinned in \_versions.hcl; latest stable at authoring — app v2.10.7). | `string` | `"2.25.5"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name (also fullnameOverride, the Service name, and the ServiceAccount name). | `string` | `"tempo"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Helm repository URL. The Tempo charts moved to grafana-community/helm-charts (Jan 2026); the old grafana/helm-charts copy is deprecated/frozen. | `string` | `"https://grafana-community.github.io/helm-charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm operation timeout (seconds). | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready (a single monolith pod schedules fine). | `bool` | `true` | no |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | Sizing toggle (cost\_profile). false = single replica per component, RF1, caches off (dev). true = RF3, zone-aware, multi-replica, caches on (prod HA). | `bool` | `false` | no |
| <a name="input_loki_datasource_uid"></a> [loki\_datasource\_uid](#input\_loki\_datasource\_uid) | Grafana UID of the Loki datasource, for the Tempo trace->logs (tracesToLogsV2) link. | `string` | `"loki"` | no |
| <a name="input_mimir_remote_write_url"></a> [mimir\_remote\_write\_url](#input\_mimir\_remote\_write\_url) | Mimir push endpoint the metrics-generator remote\_writes RED/service-graph metrics to (in-cluster gateway). Per-tenant via remote\_write\_add\_org\_id\_header. | `string` | `"http://mimir-gateway.observability.svc/api/v1/push"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy Tempo into. Must already exist (created by the observability module). | `string` | `"observability"` | no |
| <a name="input_retention_period"></a> [retention\_period](#input\_retention\_period) | Trace block retention (Tempo compactor block\_retention). Traces are high-volume; the dev default is short. | `string` | `"72h"` | no |
| <a name="input_spoke_ingest"></a> [spoke\_ingest](#input\_spoke\_ingest) | Cross-cluster spoke TRACE ingest via the shared Cilium Gateway (#628). When `tenants` is non-empty this<br/>self-routes — per spoke — a write-only HTTPRoute at `<prefix>-traces.<domain>` that force-SETS<br/>`X-Scope-OrgID` to the mapped tenant (overwriting any client value) and matches only the OTLP/HTTP trace<br/>path (`/v1/traces`), plus a CiliumNetworkPolicy admitting the Gateway Envoy's `ingress` identity to the<br/>Tempo distributor. Empty `tenants` disables it. Auth = network isolation. | <pre>object({<br/>    domain            = string<br/>    gateway_name      = string<br/>    gateway_namespace = string<br/>    tenants           = map(string) # hostname-prefix => X-Scope-OrgID tenant<br/>  })</pre> | <pre>{<br/>  "domain": "",<br/>  "gateway_name": "",<br/>  "gateway_namespace": "",<br/>  "tenants": {}<br/>}</pre> | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the Tempo WAL/local-blocks PVC. | `string` | `"gp3"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to AWS resources (and sanitized into K8s labels). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_otlp_grpc_endpoint"></a> [otlp\_grpc\_endpoint](#output\_otlp\_grpc\_endpoint) | OTLP/gRPC endpoint trace producers (the OTel collector) push to — the distributor service. |
| <a name="output_query_endpoint"></a> [query\_endpoint](#output\_query\_endpoint) | Tempo query API (the Grafana Tempo datasource) — the query-frontend service. |
| <a name="output_tempo_role_arn"></a> [tempo\_role\_arn](#output\_tempo\_role\_arn) | IAM role ARN bound to the Tempo ServiceAccount via Pod Identity (empty when not created). |
| <a name="output_traces_bucket_name"></a> [traces\_bucket\_name](#output\_traces\_bucket\_name) | S3 bucket holding Tempo trace blocks (empty when not created). |
<!-- END_TF_DOCS -->