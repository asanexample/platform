# observability-opencost (P11)

[OpenCost](https://www.opencost.io/) — in-cluster **cost allocation** (per namespace / workload / pod),
exposed as Prometheus metrics and viewable in Grafana. Part of **#102 P11** (cost). Also wires the
**true cloud cost** half (#668): the real AWS bill, incl. non-cluster spend OpenCost can't see, via
CUR → Athena, cross-account from the mgmt (payer) account — platform-hub-only, gated by `enable_cloud_cost`.

## What it does

- A single exporter pod (~10m CPU) in the shared `observability` namespace.
- Queries the existing **kube-prometheus-stack Prometheus** (`opencost.prometheus.internal`) for node/pod
  resource usage, joins it with **on-demand node pricing from the public AWS pricing API** (no AWS creds
  needed), and emits cost-allocation metrics (`opencost_*` / `node_*`, `container_cpu/memory_allocation`,
  etc.).
- Its own metrics are scraped back into Prometheus via a **ServiceMonitor**, so per-namespace/workload cost
  is queryable in PromQL and dashboardable in Grafana.

## True cloud cost (#668, `enable_cloud_cost`)

Two pieces, both cross-account (AssumeRole into the mgmt-account `cost_reader` role via Pod Identity, no
static keys):

1. **OpenCost's own `cloudCost` pipeline** — wired via a `cloud-integration.json` (AWSAssumeRole wrapping
   AWSServiceAccount). Feeds OpenCost's own UI/API only — **its cloudCost data is not Prometheus-scrapeable**,
   so this alone doesn't make anything appear in Grafana.
2. **`true-cost-exporter`** — a small long-running pod (`true-cost-exporter.tf`) that queries Athena
   directly (SELECT-only: spend by team/service/account for the current billing month, plus an EC2-only
   figure for reconciling against OpenCost's in-cluster estimate) and serves the results as Prometheus
   metrics. This is the actual Grafana-visible path — see `docs/runbooks/observability-alerts.md#true-cost-exporter`
   for the metrics/alerts, and the **Platform Cost** dashboard (`infra/modules/observability/dashboards/platform-cost.json`)
   for the panels.

Requires the `aws/cost-export` module applied first (mgmt account) — this module's `cost_reader_role_arn`
etc. inputs are that module's outputs.

## Cost & toggle

Cheap: one small pod, no standing cloud infra, no AWS API spend (public pricing) for the in-cluster half.
Gated by the `enable_cost_metrics` cost_profile knob (`create`). On for the platform cluster.
`enable_cloud_cost` is a separate opt-in (default off; `true` on the platform hub) — Athena queries cost
~$5/TB scanned but CUR data is small, so this stays a few cents/month.

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
| [aws_eks_pod_identity_association.opencost_cost_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.true_cost_exporter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.cost_reader_assumer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cost_reader_assumer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [helm_release.opencost](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map_v1.budget_status](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_config_map_v1.cost_dashboard](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_config_map_v1.true_cost_exporter_script](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_cron_job_v1.budget_enforcer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cron_job_v1) | resource |
| [kubernetes_deployment_v1.true_cost_exporter](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment_v1) | resource |
| [kubernetes_manifest.true_cost_exporter_service_monitor](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_role_binding_v1.budget_enforcer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_binding_v1) | resource |
| [kubernetes_role_v1.budget_enforcer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/role_v1) | resource |
| [kubernetes_service_account_v1.budget_enforcer](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account_v1) | resource |
| [kubernetes_service_account_v1.true_cost_exporter](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account_v1) | resource |
| [kubernetes_service_v1.true_cost_exporter](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |
| [aws_iam_policy_document.cost_reader_assumer_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_budget_enforcer_image"></a> [budget\_enforcer\_image](#input\_budget\_enforcer\_image) | Image for the budget-enforcement annotator (needs kubectl + curl + jq). ADR-091 Phase C. | `string` | `"alpine/k8s:1.31.1"` | no |
| <a name="input_budget_enforcer_schedule"></a> [budget\_enforcer\_schedule](#input\_budget\_enforcer\_schedule) | Cron schedule for the budget-enforcement annotator (ADR-091 Phase C). Cost is slow-moving — hourly is plenty. | `string` | `"17 * * * *"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name — required when enable\_cloud\_cost (Pod Identity association target). | `string` | `""` | no |
| <a name="input_cost_reader_role_arn"></a> [cost\_reader\_role\_arn](#input\_cost\_reader\_role\_arn) | ARN of the mgmt-account cost\_reader role (aws/cost-export module) this module's Pod-Identity roles assume cross-account for Athena/Glue/S3 CUR read access. Required when enable\_cloud\_cost. | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created (cost\_profile toggle — enable\_cost\_metrics). | `bool` | `true` | no |
| <a name="input_create_dashboard"></a> [create\_dashboard](#input\_create\_dashboard) | Create the Grafana cost dashboard ConfigMap. True on a cluster that runs Grafana (the hub); false on a spoke that only emits metrics. ADR-091. | `bool` | `true` | no |
| <a name="input_cur_account_id"></a> [cur\_account\_id](#input\_cur\_account\_id) | AWS account ID the CUR covers (the payer/mgmt account) — OpenCost's AthenaConfiguration.account field. Required when enable\_cloud\_cost. | `string` | `""` | no |
| <a name="input_cur_athena_database"></a> [cur\_athena\_database](#input\_cur\_athena\_database) | Glue database holding the crawled CUR table. Required when enable\_cloud\_cost. | `string` | `""` | no |
| <a name="input_cur_athena_region"></a> [cur\_athena\_region](#input\_cur\_athena\_region) | AWS region the CUR Glue database/Athena workgroup live in (CUR is us-east-1 only). | `string` | `"us-east-1"` | no |
| <a name="input_cur_athena_results_bucket"></a> [cur\_athena\_results\_bucket](#input\_cur\_athena\_results\_bucket) | S3 URI (s3://bucket/prefix/) Athena writes QUERY RESULTS to — not the CUR data bucket itself (that's implicit in the Glue table). Required when enable\_cloud\_cost. | `string` | `""` | no |
| <a name="input_cur_athena_table"></a> [cur\_athena\_table](#input\_cur\_athena\_table) | Glue table name for the crawled CUR data. Crawler-discovered, not Terraform-managed — confirm once via the Glue catalog (docs/runbooks/cost-true-spend.md) and set explicitly. Required when enable\_cloud\_cost. | `string` | `""` | no |
| <a name="input_cur_athena_workgroup"></a> [cur\_athena\_workgroup](#input\_cur\_athena\_workgroup) | Athena workgroup for CUR queries. Required when enable\_cloud\_cost. | `string` | `""` | no |
| <a name="input_dashboard_datasource_uid"></a> [dashboard\_datasource\_uid](#input\_dashboard\_datasource\_uid) | Grafana datasource uid the cost dashboard queries (the Mimir where OpenCost metrics land). ADR-091. | `string` | `"mimir"` | no |
| <a name="input_enable_budget_enforcer"></a> [enable\_budget\_enforcer](#input\_enable\_budget\_enforcer) | Run the budget-enforcement annotator (ADR-091 Phase C): an hourly CronJob that writes over-budget teams to the cost-budget-status ConfigMap the Kyverno policy reads. Enable on the spoke that runs OpenCost + the Team CRD (preprod). | `bool` | `false` | no |
| <a name="input_enable_cloud_cost"></a> [enable\_cloud\_cost](#input\_enable\_cloud\_cost) | Wire OpenCost's cloudCost pipeline (in-app only — its data isn't Prometheus-scrapeable, see the true-cost-exporter below) plus the true-cost-exporter to the mgmt-account CUR via Athena, cross-account AssumeRole + Pod Identity. #668 Phase 2a/3. Opt-in, default off. | `bool` | `false` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Chart name. | `string` | `"opencost"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | OpenCost chart version. | `string` | `"2.5.23"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | OpenCost chart repository. | `string` | `"https://opencost.github.io/opencost-helm-chart"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds. | `number` | `600` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy into (the shared observability namespace). | `string` | `"observability"` | no |
| <a name="input_prometheus_external_url"></a> [prometheus\_external\_url](#input\_prometheus\_external\_url) | External Prometheus-compatible query URL for OpenCost (e.g. the hub Mimir's query ingress, for a spoke with no in-cluster Prometheus). Empty = use the in-cluster prometheus\_service. ADR-091. | `string` | `""` | no |
| <a name="input_prometheus_namespace"></a> [prometheus\_namespace](#input\_prometheus\_namespace) | Namespace of the in-cluster Prometheus service. | `string` | `"observability"` | no |
| <a name="input_prometheus_port"></a> [prometheus\_port](#input\_prometheus\_port) | Port of the in-cluster Prometheus service. | `number` | `9090` | no |
| <a name="input_prometheus_service"></a> [prometheus\_service](#input\_prometheus\_service) | In-cluster Prometheus service name OpenCost queries for allocation data. | `string` | `"kube-prometheus-stack-prometheus"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags/labels to apply. | `map(string)` | `{}` | no |
| <a name="input_true_cost_exporter_image"></a> [true\_cost\_exporter\_image](#input\_true\_cost\_exporter\_image) | Image for the true-cost-exporter (needs python3 + pip; boto3 is installed at container start via an init container). #668 Phase 3. | `string` | `"python:3.12-alpine"` | no |
| <a name="input_true_cost_exporter_refresh_seconds"></a> [true\_cost\_exporter\_refresh\_seconds](#input\_true\_cost\_exporter\_refresh\_seconds) | How often the true-cost-exporter re-queries Athena. CUR data itself has ~24h lag, so this doesn't need to be frequent. | `number` | `21600` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | OpenCost helm release name. |
<!-- END_TF_DOCS -->