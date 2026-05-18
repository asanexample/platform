# Cilium Module

Deploys Cilium CNI on a Kubernetes cluster via Helm chart.

## Usage

```hcl
module "cilium" {
  source = "../cilium"

  create              = true
  cluster_name        = "aks-platform-ops-wus"
  resource_group_name = "rg-platform-ops-wus"
  helm_chart_version  = "1.17.2"

  aksbyocni_enabled = true
  hubble_enabled    = true
  hubble_ui_enabled = true
  gateway_api_enabled = true

  prometheus_enabled          = true
  operator_prometheus_enabled = true

  tags = {
    Environment = "ops"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "cilium" {
  source              = "../cilium"
  create              = false
  cluster_name        = ""
  resource_group_name = ""
}
```

### Minimal install without Hubble UI

```hcl
module "cilium" {
  source = "../cilium"

  cluster_name        = "aks-platform-dev-eus"
  resource_group_name = "rg-platform-dev-eus"

  hubble_ui_enabled   = false
  prometheus_enabled  = false
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster_name | Name of the AKS cluster | `string` | n/a | yes |
| resource_group_name | Name of the resource group containing the AKS cluster | `string` | n/a | yes |
| aksbyocni_enabled | Enable AKS BYOCNI integration | `bool` | `true` | no |
| cni | CNI configuration for Cilium | `any` | <pre>{<br/>  "chainingMode": null,<br/>  "exclusive": false<br/>}</pre> | no |
| cni_exclusive | Make Cilium take ownership over the container runtime CNI configuration | `bool` | `false` | no |
| create | Controls whether Cilium resources should be created | `bool` | `true` | no |
| debug | Debug configuration for Cilium | `any` | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| environment | Environment name (e.g., dev, test, prod) | `string` | `"dev"` | no |
| external_ips_enabled | Enable ExternalIPs service support | `bool` | `true` | no |
| gateway_api_enabled | Enable Gateway API support | `bool` | `true` | no |
| helm_chart | Name of the Cilium Helm chart | `string` | `"cilium"` | no |
| helm_chart_version | Version of the Cilium Helm chart | `string` | `"1.17.2"` | no |
| helm_release_name | Name of the Helm release for Cilium | `string` | `"cilium"` | no |
| helm_repository | Repository URL for the Cilium Helm chart | `string` | `"https://helm.cilium.io/"` | no |
| helm_timeout | Timeout for Helm operations in seconds | `number` | `1200` | no |
| helm_wait | Whether to wait for Helm release to complete | `bool` | `true` | no |
| hubble_enabled | Enable Hubble | `bool` | `true` | no |
| hubble_listen_address | Hubble listen address | `string` | `":4244"` | no |
| hubble_metrics_enable_open_metrics | Enable OpenMetrics format for Hubble metrics | `bool` | `false` | no |
| hubble_metrics_enabled | List of Hubble metrics to enable | `list(string)` | <pre>[<br/>  "dns",<br/>  "drop",<br/>  "tcp",<br/>  "flow",<br/>  "port-distribution",<br/>  "icmp",<br/>  "dns:labelsContext=source_namespace,destination_namespace",<br/>  "drop:labelsContext=source_namespace,destination_namespace",<br/>  "httpV2:sourceContext=workload-name|pod-name|reserved-identity;destinationContext=workload-name|pod-name|reserved-identity;labelsContext=source_namespace,destination_namespace,traffic_direction"<br/>]</pre> | no |
| hubble_relay_enabled | Enable Hubble Relay | `bool` | `true` | no |
| hubble_tls_auto_enabled | Enable automatic TLS certificate generation for Hubble | `bool` | `true` | no |
| hubble_tls_auto_method | Method to auto-generate TLS certificates (cronJob or certmanager) | `string` | `"cronJob"` | no |
| hubble_tls_cert_validity_duration | Validity duration of the Hubble TLS certificates in days | `number` | `1095` | no |
| hubble_tls_schedule | Cron schedule for Hubble TLS certificate generation | `string` | `"0 0 1 */4 *"` | no |
| hubble_ui_enabled | Enable Hubble UI | `bool` | `true` | no |
| identityAllocationMode | The method to use for identity allocation (CRD or kvstore) | `string` | `"crd"` | no |
| kube_proxy_replacement | KubeProxy replacement mode (false, 'strict', 'partial', 'probe') | `string` | `"false"` | no |
| namespace | Kubernetes namespace to install Cilium into | `string` | `"kube-system"` | no |
| node_port_enabled | Enable NodePort service support | `bool` | `true` | no |
| nodeinit_enabled | Enable node initialization DaemonSet | `bool` | `true` | no |
| operator_prometheus_enabled | Enable Prometheus metrics for Cilium operator | `bool` | `true` | no |
| operator_resources_limits_cpu | CPU limit for Cilium operator | `string` | `"500m"` | no |
| operator_resources_limits_memory | Memory limit for Cilium operator | `string` | `"512Mi"` | no |
| operator_resources_requests_cpu | CPU request for Cilium operator | `string` | `"50m"` | no |
| operator_resources_requests_memory | Memory request for Cilium operator | `string` | `"64Mi"` | no |
| workload | Workload name to use for resource naming | `string` | `""` | no |
| prometheus_enabled | Enable Prometheus metrics for Cilium agent | `bool` | `true` | no |
| prometheus_service_monitor_enabled | Enable Prometheus ServiceMonitor for Cilium agent | `bool` | `true` | no |
| region_abbv | Abbreviated name of the region (e.g., eus for eastus) | `string` | `""` | no |
| resources_limits_cpu | CPU limit for Cilium agent | `string` | `"1000m"` | no |
| resources_limits_memory | Memory limit for Cilium agent | `string` | `"1Gi"` | no |
| resources_requests_cpu | CPU request for Cilium agent | `string` | `"100m"` | no |
| resources_requests_memory | Memory request for Cilium agent | `string` | `"128Mi"` | no |
| socket_lb_host_namespace_only | Force socket LB in host namespace only | `bool` | `true` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| tls | TLS configuration for Cilium | `any` | <pre>{<br/>  "enabled": false<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cilium_values | The values used for the Cilium Helm chart |
| helm_release_name | Name of the Cilium Helm release |
| helm_release_status | Status of the Cilium Helm release |
| helm_release_version | Version of the Cilium Helm chart deployed |
| namespace | Kubernetes namespace where Cilium is installed |
<!-- END_TF_DOCS -->

## Dependencies

- `aks_core` (or any Kubernetes cluster) — the cluster must exist and be reachable before Cilium is deployed.

## Notes

- Cloud-agnostic module; works on any Kubernetes cluster, but defaults target AKS with BYOCNI mode (`aksbyocni_enabled = true`, `nodeinit_enabled = true`).
- On AKS, the cluster must be provisioned with `network_plugin = "none"` so Cilium can take over CNI duties.
- Requires `kubelogin` on the machine running Terraform when targeting Azure (for AAD-integrated kubeconfig auth).
- The Helm release uses `atomic = true` — a failed deploy automatically rolls back.
