# observability-policy-reporter (P12, #93)

[policy-reporter](https://kyverno.github.io/policy-reporter/) — watches Kyverno's `PolicyReport`/
`ClusterPolicyReport` CRs (ADR-014's admission engine, both validate/mutate and cosign
verifyImages/verifyAttestations) and exposes them as Prometheus metrics + Grafana dashboards. Part of
**#102 P12**, closes **#93**.

## What it does

- A single watcher pod (~10m CPU) in the shared `observability` namespace. No Kyverno-side config
  needed — it just watches the report CRs that already exist cluster-wide (`kubectl get policyreport
  -A` / `kubectl get clusterpolicyreport`).
- Emits `policy_report_result` / `cluster_policy_report_result` series in `detailed` mode (labels:
  namespace, policy, rule, kind, name, status, severity, category, source) — scraped by the local
  Prometheus/prometheus-agent (`serviceMonitorSelectorNilUsesHelmValues=false`) and remote_written to
  the hub Mimir under this cluster's tenant, same as every other add-on.
- Ships its own bundled Grafana dashboards (Overview / PolicyReport details / ClusterPolicyReport
  details) via the same sidecar ConfigMap convention this repo already uses
  (`grafana_dashboard=1`/`grafana_folder`) — every panel carries a `$cluster` filter out of the box
  (`grafana.dashboards.multicluster`), matching the house dashboard convention (#151).

## Hub vs spoke

Same split as OpenCost (P11): the **hub** (platform) runs `create_dashboards = true` so Grafana can
render them; the **preprod spoke** runs `create_dashboards = false` and only emits metrics — the hub's
federated `Mimir (all clusters)` datasource renders the spoke's PolicyReport data too, no per-cluster
dashboard needed.

## Toggle

Gated by `enable_policy_reporting` (cost_profile-style toggle in `_base.hcl`/`env.hcl`) — on for both
platform and preprod today; cheap (one small watcher pod, no cloud spend).

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
| [helm_release.policy_reporter](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created (cost/policy-reporting toggle — enable\_policy\_reporting). | `bool` | `true` | no |
| <a name="input_create_dashboards"></a> [create\_dashboards](#input\_create\_dashboards) | Ship the chart's bundled Grafana dashboards via the sidecar ConfigMap pattern. True on a cluster that runs Grafana (the hub); false on a spoke that only emits metrics for the hub's federated view to render. | `bool` | `true` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Chart name. | `string` | `"policy-reporter"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | policy-reporter chart version. | `string` | `"3.7.4"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | policy-reporter chart repository. | `string` | `"https://kyverno.github.io/policy-reporter"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds. | `number` | `300` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy into (the shared observability namespace). | `string` | `"observability"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags/labels to apply. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | policy-reporter helm release name. |
<!-- END_TF_DOCS -->