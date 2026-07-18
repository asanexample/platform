# Prometheus Operator CRDs

Installs the Prometheus Operator custom resource definitions (`ServiceMonitor`, `PodMonitor`,
`PrometheusRule`, `Probe`, `ScrapeConfig`, …) via the CRD-only `prometheus-operator-crds` Helm
chart, **early** in the deployment DAG.

## Why this exists

The `ServiceMonitor` (and sibling) CRDs normally ship with the `kube-prometheus-stack` chart that
the `observability` unit installs — but that unit runs late. Many earlier workloads (keycloak,
argo-rollouts, observability spokes, …) render a `ServiceMonitor` in their own Helm release, and the
Terraform Helm provider fails at manifest build if the CRD is not yet in the cluster
(`no matches for kind "ServiceMonitor" ... ensure CRDs are installed first`). On a from-scratch
bootstrap this deadlocks. Owning the CRDs in a dedicated early release breaks the cycle.

Pin `chart_version` to the release whose appVersion matches the operator version used by the
observability `kube-prometheus-stack` (e.g. chart `30.0.1` = operator `v0.92.1` = stack `87.5.0`), and
set `crds.enabled = false` on the stack releases so this is the single CRD owner (no Helm ownership
conflict).

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
| [helm_release.crds](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | prometheus-operator-crds Helm chart version. Pin to the release whose appVersion matches the kube-prometheus-stack operator version used by the observability stack (e.g. chart 30.0.1 = operator v0.92.1 = kube-prometheus-stack 87.5.0), so the CRD schemas match what the stack expects. | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Name of the prometheus-operator-crds Helm release (a dependency anchor for units that create ServiceMonitors/PrometheusRules) |
<!-- END_TF_DOCS -->
