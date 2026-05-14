# ArgoCD Deployment for Ops/Westus

This directory contains the Terragrunt configuration for deploying ArgoCD on the AKS cluster in the `ops/westus` environment.

## Overview

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. This configuration deploys ArgoCD with high availability on the AKS cluster and bootstraps essential applications.

## Dependencies

This module depends on:
- `../aks_core` - The core AKS cluster
- `../cilium` - The Cilium CNI network

## Usage

To deploy ArgoCD on the ops/westus environment:

```bash
# Navigate to the ArgoCD directory
cd infra/live/azure/ops/westus/argocd

# Plan the deployment
terragrunt plan

# Apply the configuration
terragrunt apply
```

## Accessing ArgoCD

After deployment, you can access ArgoCD UI using one of these methods:

1. **Port forwarding:**
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```
   Then access it at: https://localhost:8080

2. **Using the domain name (after DNS is configured):**
   Access at: https://argocd-ops-wus.example.com

## Initial Admin Credentials

The initial admin password can be retrieved with:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Bootstrapped Applications

This deployment automatically bootstraps the following applications:

1. **cert-manager** - Kubernetes certificate management
2. **external-dns** - DNS automation for Kubernetes Ingress
3. **external-secrets** - Kubernetes integration with external secret stores

## Configuration

The ArgoCD deployment is configured with:

- High availability mode enabled
- RBAC with read-only default access
- Integration with Cilium networking

For additional configuration, please modify the `inputs` block in `terragrunt.hcl`. 