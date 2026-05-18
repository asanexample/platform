# Cilium CNI Deployment

This directory contains the Terragrunt configuration for deploying Cilium CNI on the AKS cluster in the `ops/westus` environment.

## Overview

Cilium is a CNI (Container Network Interface) that provides networking, security, and observability for Kubernetes clusters. This configuration deploys Cilium as the CNI for the AKS cluster using the "Bring Your Own CNI" (BYOCNI) approach.

## Dependencies

This module depends on:
- `../aks_core` - The core AKS cluster configuration 

## Key Features Configured

- **TLS Enabled**: TLS is enabled for secure communication
- **Debug Mode**: Debug mode is enabled to help diagnose any issues
- **AKS BYOCNI Mode**: Configured to work with AKS Bring Your Own CNI mode
- **Identity Allocation**: Using CRD identity allocation mode for better reliability
- **Resource Limits**: Configured with appropriate resource limits for both agent and operator

## Usage

To apply this configuration:

```bash
cd infra/live/azure/ops/westus/cilium
terragrunt plan
terragrunt apply
```

## Troubleshooting

If you encounter networking issues after deployment, check:
- The Cilium agent and operator pods in the kube-system namespace
- TLS handshake errors in the logs
- Node initialization status

Common commands for troubleshooting:
```bash
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl logs -n kube-system -l k8s-app=cilium
``` 