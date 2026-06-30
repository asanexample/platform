# observability-opencost (P11, part 1)

[OpenCost](https://www.opencost.io/) — in-cluster **cost allocation** (per namespace / workload / pod),
exposed as Prometheus metrics and viewable in Grafana. Part of **#102 P11** (cost). This is the
**in-cluster** half; the heavier **AWS CUR → Athena → Grafana** half (true cloud spend by `Team` tag) is a
separate follow-on.

## What it does

- A single exporter pod (~10m CPU) in the shared `observability` namespace.
- Queries the existing **kube-prometheus-stack Prometheus** (`opencost.prometheus.internal`) for node/pod
  resource usage, joins it with **on-demand node pricing from the public AWS pricing API** (no AWS creds
  needed), and emits cost-allocation metrics (`opencost_*` / `node_*`, `container_cpu/memory_allocation`,
  etc.).
- Its own metrics are scraped back into Prometheus via a **ServiceMonitor**, so per-namespace/workload cost
  is queryable in PromQL and dashboardable in Grafana.

## Cost & toggle

Cheap: one small pod, no standing cloud infra, no AWS API spend (public pricing). Gated by the
`enable_cost_metrics` cost_profile knob (`create`). On for the platform cluster.

Cloud-cost (`cloudCost`, CUR-based) is intentionally **off** — it needs a CUR + Athena setup (the P11 part-2
follow-on). For ad-hoc cloud spend today, the AWS console / Cost Explorer remains the source.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.opencost](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map_v1.cost_dashboard](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created (cost\_profile toggle — enable\_cost\_metrics). | `bool` | `true` | no |
| <a name="input_dashboard_datasource_uid"></a> [dashboard\_datasource\_uid](#input\_dashboard\_datasource\_uid) | Grafana datasource uid the cost dashboard queries (the Mimir where OpenCost metrics land). ADR-091. | `string` | `"mimir"` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Chart name. | `string` | `"opencost"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | OpenCost chart version. | `string` | `"2.5.23"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | OpenCost chart repository. | `string` | `"https://opencost.github.io/opencost-helm-chart"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds. | `number` | `600` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy into (the shared observability namespace). | `string` | `"observability"` | no |
| <a name="input_prometheus_namespace"></a> [prometheus\_namespace](#input\_prometheus\_namespace) | Namespace of the in-cluster Prometheus service. | `string` | `"observability"` | no |
| <a name="input_prometheus_port"></a> [prometheus\_port](#input\_prometheus\_port) | Port of the in-cluster Prometheus service. | `number` | `9090` | no |
| <a name="input_prometheus_service"></a> [prometheus\_service](#input\_prometheus\_service) | In-cluster Prometheus service name OpenCost queries for allocation data. | `string` | `"kube-prometheus-stack-prometheus"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags/labels to apply. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | OpenCost helm release name. |
<!-- END_TF_DOCS -->