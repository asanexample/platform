# Cilium Helm Module

This Terraform module deploys [Cilium](https://cilium.io/) CNI on an Azure Kubernetes Service (AKS) cluster using Helm.

## Features

- Deploys Cilium on AKS with Bring Your Own CNI (BYOCNI) mode
- Configurable Hubble for network visibility and monitoring
- Prometheus metrics integration
- Gateway API support
- Resource management for Cilium agent and operator

## Usage

```hcl
module "cilium" {
  source = "../modules/kubernetes/cilium"

  # AKS cluster details
  cluster_name        = "my-aks-cluster"
  resource_group_name = "my-resource-group"

  # Cilium configuration
  helm_chart_version = "1.17.2"
  
  # Enable AKS BYOCNI integration
  aksbyocni_enabled = true
  
  # Optional: Customize Hubble
  hubble_enabled = true
  hubble_ui_enabled = true
  
  # Optional: Configure monitoring
  prometheus_enabled = true
  prometheus_service_monitor_enabled = true
}
```

## Prerequisites

Before using this module, you need:

1. An existing AKS cluster created with the following settings:
   - Azure CNI networking
   - Network policy set to "none" (not Azure or Calico)
   
2. Terraform providers:
   - `azurerm` provider
   - `helm` provider
   - `kubernetes` provider

## Module Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the AKS cluster | string | - | yes |
| resource_group_name | Name of the resource group containing the AKS cluster | string | - | yes |
| helm_release_name | Name of the Helm release for Cilium | string | "cilium" | no |
| helm_repository | Repository URL for the Cilium Helm chart | string | "https://helm.cilium.io/" | no |
| helm_chart | Name of the Cilium Helm chart | string | "cilium" | no |
| helm_chart_version | Version of the Cilium Helm chart | string | "1.17.2" | no |
| namespace | Kubernetes namespace to install Cilium into | string | "kube-system" | no |
| aksbyocni_enabled | Enable AKS BYOCNI integration | bool | true | no |
| gateway_api_enabled | Enable Gateway API support | bool | true | no |
| hubble_enabled | Enable Hubble | bool | true | no |

See `variables.tf` for a complete list of configurable variables.

## Module Outputs

| Name | Description |
|------|-------------|
| helm_release_status | Status of the Cilium Helm release |
| helm_release_name | Name of the Cilium Helm release |
| helm_release_version | Version of the Cilium Helm chart deployed |
| namespace | Kubernetes namespace where Cilium is installed |

## Dependencies

This module depends on:
- An existing AKS cluster
- Helm provider
- Kubernetes provider

## Notes

- Cilium will be deployed in the `kube-system` namespace by default
- The module assumes that you're using AKS with BYOCNI (Bring Your Own CNI)
- For production environments, consider adjusting resource requests and limits 