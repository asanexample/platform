# Cilium CNI Installation

This Terragrunt module installs Cilium CNI on the AKS cluster using the Helm provider.

## Configuration Details

### Purpose
Installs Cilium v1.17.2 CNI on an AKS cluster to provide networking, security, and observability capabilities. Cilium uses eBPF to deliver features like network policy enforcement, load balancing, and observability without modifying application code.

### Dependencies
This module depends on:
- **naming**: For consistent resource naming
- **resource_group**: For resource group info
- **aks_core**: For the AKS cluster details necessary to configure Kubernetes providers

### Key Configuration Settings
- **Namespace**: Installs Cilium in `kube-system` namespace
- **CNI Configuration**: 
  - AKS integration enabled
  - VXLAN tunnel mode for encapsulation
  - Kubernetes IPAM mode
  - Strict kube-proxy replacement
- **Observability**:
  - Hubble enabled with UI and relay components
  - Prometheus metrics enabled
- **Installation Parameters**:
  - Helm timeout: 1200 seconds
  - Waits for deployment completion

## Usage Example

```bash
# To apply just this module
cd cilium
terragrunt apply

# To verify installation
kubectl get pods -n kube-system -l k8s-app=cilium
```

## Dependencies on this Module
No other modules depend on this module. This is an endpoint module that configures the networking capabilities of the AKS cluster created by the aks_core module.

## Notes
- Ensure AKS cluster is configured with `network_plugin = "none"` to allow Cilium to take over networking
- After installation, network policies will be enforced by Cilium 