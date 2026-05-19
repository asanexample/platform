# Cilium

Deploys Cilium CNI on a Kubernetes cluster via Helm with cloud-specific configuration for AWS (EKS), Azure (AKS), and GCP (GKE).

## Usage

```hcl
module "cilium" {
  source = "../cilium"

  create         = true
  cloud_provider = "aws"
  cluster_name   = "eks-platform-dev-use1"

  k8s_service_host = "ABCDEF1234.gr7.us-east-1.eks.amazonaws.com"
  k8s_service_port = "443"

  helm_chart_version  = "1.17.2"
  gateway_api_enabled = true
  hubble_enabled      = true
  hubble_ui_enabled   = true

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled module

```hcl
module "cilium" {
  source       = "../cilium"
  create       = false
  cluster_name = ""
}
```

### Azure (AKS)

```hcl
module "cilium" {
  source = "../cilium"

  create              = true
  cloud_provider      = "azure"
  cluster_name        = "aks-platform-ops-wus"
  resource_group_name = "rg-platform-ops-wus"

  helm_chart_version  = "1.17.2"
  gateway_api_enabled = true
  hubble_enabled      = true
  hubble_ui_enabled   = true

  tags = {
    Environment = "ops"
    ManagedBy   = "Terragrunt"
  }
}
```

### GCP (GKE)

```hcl
module "cilium" {
  source = "../cilium"

  create         = true
  cloud_provider = "gcp"
  cluster_name   = "gke-platform-dev-usc1"

  k8s_service_host = "10.0.0.1"
  k8s_service_port = "443"

  helm_chart_version  = "1.17.2"
  gateway_api_enabled = true
  hubble_enabled      = true
  hubble_ui_enabled   = true

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

<!-- BEGIN_TF_DOCS -->
# Cilium Helm Module

Deploys Cilium CNI via Helm. Supports Azure (AKS), AWS (EKS), and GCP (GKE).

## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.17.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloud_provider"></a> [cloud\_provider](#input\_cloud\_provider) | Cloud provider for platform-specific CNI config | `string` | `"azure"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the Kubernetes cluster | `string` | n/a | yes |
| <a name="input_cni"></a> [cni](#input\_cni) | CNI configuration for Cilium | `any` | <pre>{<br/>  "chainingMode": null,<br/>  "exclusive": false<br/>}</pre> | no |
| <a name="input_cni_exclusive"></a> [cni\_exclusive](#input\_cni\_exclusive) | Make Cilium take ownership over the container runtime CNI configuration | `bool` | `false` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether Cilium resources should be created | `bool` | `true` | no |
| <a name="input_debug"></a> [debug](#input\_debug) | Debug configuration for Cilium | `any` | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., dev, test, prod) | `string` | `"dev"` | no |
| <a name="input_external_ips_enabled"></a> [external\_ips\_enabled](#input\_external\_ips\_enabled) | Enable ExternalIPs service support | `bool` | `true` | no |
| <a name="input_gateway_api_enabled"></a> [gateway\_api\_enabled](#input\_gateway\_api\_enabled) | Enable Gateway API support | `bool` | `true` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Name of the Cilium Helm chart | `string` | `"cilium"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Version of the Cilium Helm chart | `string` | `"1.17.2"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Name of the Helm release for Cilium | `string` | `"cilium"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Repository URL for the Cilium Helm chart | `string` | `"https://helm.cilium.io/"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds | `number` | `1200` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Whether to wait for Helm release to complete | `bool` | `true` | no |
| <a name="input_hubble_enabled"></a> [hubble\_enabled](#input\_hubble\_enabled) | Enable Hubble | `bool` | `true` | no |
| <a name="input_hubble_listen_address"></a> [hubble\_listen\_address](#input\_hubble\_listen\_address) | Hubble listen address | `string` | `":4244"` | no |
| <a name="input_hubble_metrics_enable_open_metrics"></a> [hubble\_metrics\_enable\_open\_metrics](#input\_hubble\_metrics\_enable\_open\_metrics) | Enable OpenMetrics format for Hubble metrics | `bool` | `false` | no |
| <a name="input_hubble_metrics_enabled"></a> [hubble\_metrics\_enabled](#input\_hubble\_metrics\_enabled) | List of Hubble metrics to enable | `list(string)` | <pre>[<br/>  "dns",<br/>  "drop",<br/>  "tcp",<br/>  "flow",<br/>  "port-distribution",<br/>  "icmp",<br/>  "dns:labelsContext=source_namespace,destination_namespace",<br/>  "drop:labelsContext=source_namespace,destination_namespace",<br/>  "httpV2:sourceContext=workload-name|pod-name|reserved-identity;destinationContext=workload-name|pod-name|reserved-identity;labelsContext=source_namespace,destination_namespace,traffic_direction"<br/>]</pre> | no |
| <a name="input_hubble_relay_enabled"></a> [hubble\_relay\_enabled](#input\_hubble\_relay\_enabled) | Enable Hubble Relay | `bool` | `true` | no |
| <a name="input_hubble_tls_auto_enabled"></a> [hubble\_tls\_auto\_enabled](#input\_hubble\_tls\_auto\_enabled) | Enable automatic TLS certificate generation for Hubble | `bool` | `true` | no |
| <a name="input_hubble_tls_auto_method"></a> [hubble\_tls\_auto\_method](#input\_hubble\_tls\_auto\_method) | Method to auto-generate TLS certificates (cronJob or certmanager) | `string` | `"cronJob"` | no |
| <a name="input_hubble_tls_cert_validity_duration"></a> [hubble\_tls\_cert\_validity\_duration](#input\_hubble\_tls\_cert\_validity\_duration) | Validity duration of the Hubble TLS certificates in days | `number` | `1095` | no |
| <a name="input_hubble_tls_schedule"></a> [hubble\_tls\_schedule](#input\_hubble\_tls\_schedule) | Cron schedule for Hubble TLS certificate generation | `string` | `"0 0 1 */4 *"` | no |
| <a name="input_hubble_ui_enabled"></a> [hubble\_ui\_enabled](#input\_hubble\_ui\_enabled) | Enable Hubble UI | `bool` | `true` | no |
| <a name="input_identityAllocationMode"></a> [identityAllocationMode](#input\_identityAllocationMode) | The method to use for identity allocation (CRD or kvstore) | `string` | `"crd"` | no |
| <a name="input_k8s_service_host"></a> [k8s\_service\_host](#input\_k8s\_service\_host) | Kubernetes API server hostname (required for BYOCNI — in-cluster service IP unreachable before CNI exists) | `string` | `""` | no |
| <a name="input_k8s_service_port"></a> [k8s\_service\_port](#input\_k8s\_service\_port) | Kubernetes API server port | `string` | `"443"` | no |
| <a name="input_kube_proxy_replacement"></a> [kube\_proxy\_replacement](#input\_kube\_proxy\_replacement) | KubeProxy replacement mode (false, 'strict', 'partial', 'probe') | `string` | `"false"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to install Cilium into | `string` | `"kube-system"` | no |
| <a name="input_node_port_enabled"></a> [node\_port\_enabled](#input\_node\_port\_enabled) | Enable NodePort service support | `bool` | `true` | no |
| <a name="input_operator_prometheus_enabled"></a> [operator\_prometheus\_enabled](#input\_operator\_prometheus\_enabled) | Enable Prometheus metrics for Cilium operator | `bool` | `true` | no |
| <a name="input_operator_resources_limits_cpu"></a> [operator\_resources\_limits\_cpu](#input\_operator\_resources\_limits\_cpu) | CPU limit for Cilium operator | `string` | `"500m"` | no |
| <a name="input_operator_resources_limits_memory"></a> [operator\_resources\_limits\_memory](#input\_operator\_resources\_limits\_memory) | Memory limit for Cilium operator | `string` | `"512Mi"` | no |
| <a name="input_operator_resources_requests_cpu"></a> [operator\_resources\_requests\_cpu](#input\_operator\_resources\_requests\_cpu) | CPU request for Cilium operator | `string` | `"50m"` | no |
| <a name="input_operator_resources_requests_memory"></a> [operator\_resources\_requests\_memory](#input\_operator\_resources\_requests\_memory) | Memory request for Cilium operator | `string` | `"64Mi"` | no |
| <a name="input_prometheus_enabled"></a> [prometheus\_enabled](#input\_prometheus\_enabled) | Enable Prometheus metrics for Cilium agent | `bool` | `true` | no |
| <a name="input_prometheus_service_monitor_enabled"></a> [prometheus\_service\_monitor\_enabled](#input\_prometheus\_service\_monitor\_enabled) | Enable Prometheus ServiceMonitor for Cilium agent | `bool` | `true` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviated name of the region (e.g., eus for eastus) | `string` | `""` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the Azure resource group (only required for Azure) | `string` | `""` | no |
| <a name="input_resources_limits_cpu"></a> [resources\_limits\_cpu](#input\_resources\_limits\_cpu) | CPU limit for Cilium agent | `string` | `"1000m"` | no |
| <a name="input_resources_limits_memory"></a> [resources\_limits\_memory](#input\_resources\_limits\_memory) | Memory limit for Cilium agent | `string` | `"1Gi"` | no |
| <a name="input_resources_requests_cpu"></a> [resources\_requests\_cpu](#input\_resources\_requests\_cpu) | CPU request for Cilium agent | `string` | `"100m"` | no |
| <a name="input_resources_requests_memory"></a> [resources\_requests\_memory](#input\_resources\_requests\_memory) | Memory request for Cilium agent | `string` | `"128Mi"` | no |
| <a name="input_socket_lb_host_namespace_only"></a> [socket\_lb\_host\_namespace\_only](#input\_socket\_lb\_host\_namespace\_only) | Force socket LB in host namespace only | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_tls"></a> [tls](#input\_tls) | TLS configuration for Cilium | `any` | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource naming | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cilium_values"></a> [cilium\_values](#output\_cilium\_values) | The values used for the Cilium Helm chart |
| <a name="output_helm_release_name"></a> [helm\_release\_name](#output\_helm\_release\_name) | Name of the Cilium Helm release |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the Cilium Helm release |
| <a name="output_helm_release_version"></a> [helm\_release\_version](#output\_helm\_release\_version) | Version of the Cilium Helm chart deployed |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where Cilium is installed |
<!-- END_TF_DOCS -->

## Dependencies

- Helm provider must be configured by the caller with valid cluster credentials.
- A Kubernetes cluster (EKS, AKS, or GKE) must exist and be reachable.

## Notes

- Cloud-specific Helm values are applied automatically based on `cloud_provider` (aws=ENI mode, azure=AKS BYOCNI, gcp=GKE native routing).
- On AWS, `hubble.tls.auto.method` is set to `"helm"` instead of the default `"cronJob"` to avoid post-install hook issues with BYOCNI bootstrapping.
- On EKS, `k8s_service_host` must be set to the cluster API endpoint because the in-cluster Kubernetes service IP is unreachable before the CNI exists.
- On Azure, the AKS cluster must be provisioned with `network_plugin = "none"`.
- The Helm release uses `atomic = true` -- a failed deploy automatically rolls back.
