# Cilium CNI Deployment

This Terragrunt configuration deploys Cilium as the Container Network Interface (CNI) for your Azure Kubernetes Service (AKS) cluster. Cilium is deployed using Helm and configured to operate in AKS BYOCNI (Bring Your Own CNI) mode.

## Prerequisites

- The AKS cluster must already be deployed
- The AKS cluster should be configured with network policy set to "none" (not Azure or Calico)

## Features

- **BYOCNI Integration**: Deploys Cilium in AKS BYOCNI mode
- **Gateway API**: Support for Kubernetes Gateway API
- **Observability**: Hubble for network flow visualization and monitoring
- **Monitoring**: Prometheus metrics integration with ServiceMonitor
- **Resource Management**: Configurable resource limits and requests

## Usage

### Deploying Cilium

```bash
# Initialize Terragrunt to set up the necessary state and provider configurations
terragrunt init

# Plan the deployment
terragrunt plan

# Apply the configuration to deploy Cilium
terragrunt apply
```

Cilium depends on the AKS cluster deployment. Terragrunt will automatically handle this dependency by ensuring the AKS cluster is deployed before Cilium.

### Destroying the Cilium Deployment

```bash
# Remove Cilium
terragrunt destroy
```

## Configuration Options

The module is configured through the `terragrunt.hcl` file. Key configuration options include:

- `helm_chart_version`: The version of the Cilium Helm chart to deploy
- `aksbyocni_enabled`: Controls AKS BYOCNI integration
- `hubble_enabled`: Enables network flow visualization with Hubble
- `prometheus_enabled`: Enables Prometheus metrics

See the `terragrunt.hcl` file for a complete list of configuration options.

## Notes

- Cilium is installed in the `kube-system` namespace by default
- Default resource limits are configured for both Cilium agent and operator
- The configuration includes monitoring settings for integration with Prometheus 