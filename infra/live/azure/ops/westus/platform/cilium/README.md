# Cilium CNI - West US (Platform)

## Overview

Deploys Cilium as the CNI for the AKS cluster via Helm in the platform environment, West US region.

## Configuration Details

### Purpose

- Installs Cilium into the BYOCNI AKS cluster with Azure-native settings
- Configures CRD-based identity allocation for network policy enforcement
- Enables TLS and debug mode for secure communication and diagnostics

### Dependencies

- **aks_core**: provides cluster name, resource group, API host, and CA certificate for Helm and Kubernetes provider authentication

### Key Configuration Settings

- **Cilium**:
  - cloud_provider: `azure`
  - CNI chaining mode: `none` (exclusive)
  - Identity allocation: CRD-based
  - TLS: enabled
  - Debug: enabled
  - Chart version: pinned via shared `helm_versions.cilium`

- **Networking Features**:
  - NodePort: enabled
  - External IPs: enabled
  - Gateway API: disabled
  - kube-proxy replacement: disabled
  - Socket LB: host namespace only

- **Observability**:
  - Prometheus: disabled
  - Hubble: disabled (relay, UI, and metrics all off)

- **Resources**:
  - Agent: 100m-1000m CPU, 128Mi-1Gi memory
  - Operator: 50m-500m CPU, 64Mi-512Mi memory

- **Provider Auth**:
  - Helm and Kubernetes providers use exec-based auth via `kubelogin` with Azure CLI

## Usage

```bash
cd infra/live/azure/ops/westus/platform/cilium
terragrunt plan
terragrunt apply
```

## Dependencies on this Configuration

- **aks_node_pools**: nodes require the CNI to be installed before reaching a Ready state

## Implementation Notes

The Helm and Kubernetes providers authenticate using `kubelogin` with the `azurecli` login mode. The AKS cluster must be configured with `network_plugin = "none"` (BYOCNI mode) before Cilium is deployed. This environment was renamed from "ops" to "platform"; the directory path still reflects the original name.
