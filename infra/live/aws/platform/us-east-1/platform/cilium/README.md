# Cilium

Deploys Cilium as the CNI for the EKS cluster (BYOCNI mode), enabling pod networking before nodes join.

## Module

`infra/modules/cilium`

## Dependencies

- `eks` -- `../eks`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `cloud_provider` | `aws` | AWS ENI integration mode |
| `k8s_service_host` | EKS endpoint (https:// stripped) | Required for kubeProxyReplacement |
| `k8s_service_port` | `443` | |
| `helm_wait` | `false` | No nodes exist yet to schedule the DaemonSet; waiting would hang |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
