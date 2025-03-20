# Cilium CNI Installation Module

This module installs [Cilium](https://cilium.io/) CNI using the Helm provider on an AKS cluster.

## Description

Cilium is an open-source project that provides eBPF-based networking, security, and observability for container workloads. This module simplifies the installation of Cilium on an AKS cluster by using Terraform and the Helm provider.

The module is designed to work with AKS clusters that have `network_plugin` set to `"none"` to allow Cilium to take over the networking responsibilities.

## Prerequisites

- An AKS cluster with `network_plugin` set to `"none"`
- Kubernetes and Helm providers (configured by Terragrunt when used with this project)

## Provider Configuration

This module requires the Kubernetes and Helm providers to be configured. When used with Terragrunt in this project, the provider configuration is automatically handled through generate blocks that create provider configuration files.

The required provider configuration includes:
- `kubernetes` provider with AKS cluster authentication details
- `helm` provider with Kubernetes backend configured for AKS

## Usage

```hcl
module "cilium" {
  source = "../../modules/azure/kubernetes/cilium"

  # Required parameters
  kubernetes_host = module.aks_core.host

  # Optional parameters
  chart_version = "1.17.2"
  namespace     = "kube-system"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| namespace | Kubernetes namespace where Cilium will be installed | `string` | `"kube-system"` | no |
| namespace_labels | Labels to apply to the Cilium namespace | `map(string)` | `{}` | no |
| chart_version | Version of the Cilium Helm chart to install | `string` | `"1.17.2"` | no |
| helm_timeout | Timeout for Helm operations in seconds | `number` | `900` | no |
| wait | Whether to wait for the release to be deployed | `bool` | `true` | no |
| values_file | Path to a file containing custom Helm values | `string` | `""` | no |
| values_content | Raw Helm values content | `string` | `""` | no |
| set_values | Map of value pairs to pass to the Helm chart | `map(string)` | `{}` | no |
| kubernetes_host | Kubernetes API server host | `string` | n/a | yes |
| kubernetes_port | Kubernetes API server port | `string` | `"443"` | no |
| operator_replicas | Number of replicas for Cilium operator | `string` | `"2"` | no |
| prometheus_enabled | Enable the Prometheus metrics in Cilium | `bool` | `true` | no |
| prometheus_service_monitor_enabled | Enable the Prometheus ServiceMonitor resources | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| release_name | Name of the Helm release |
| release_namespace | Namespace of the Helm release |
| release_status | Status of the Helm release |
| release_version | Version of the Helm release |

## Default Configuration

When no custom configuration is provided, the module applies the following default Cilium settings:

- AKS integration enabled
- VXLAN tunnel mode
- Kubernetes IPAM mode
- Strict kube-proxy replacement
- Hubble (observability) enabled with UI and relay
- Node initialization enabled
- Prometheus metrics enabled

## Example with Custom Values

```hcl
module "cilium" {
  source = "../../modules/azure/kubernetes/cilium"

  kubernetes_host = module.aks_core.host
  chart_version   = "1.17.2"
  namespace       = "kube-system"
  
  set_values = {
    "aks.enabled"              = "true"
    "tunnel"                   = "vxlan"
    "ipam.mode"                = "kubernetes"
    "kubeProxyReplacement"     = "strict"
    "hubble.enabled"           = "true"
    "hubble.relay.enabled"     = "true"
    "hubble.ui.enabled"        = "true"
    "operator.replicas"        = "2"
    "nodeinit.enabled"         = "true"
    "prometheus.enabled"       = "true"
    "l7Proxy"                  = "false"
    "installNoConntrackIptablesRules" = "true"
  }
}
``` 