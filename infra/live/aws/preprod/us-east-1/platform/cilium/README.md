# cilium

Deploys Cilium as the CNI for the preprod EKS cluster. Must be applied before node groups can join the cluster (BYOCNI).

## Module

`infra/modules/cilium`

## Dependencies

- `eks` — `../eks`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `cloud_provider` | `"aws"` | Configures AWS-specific Cilium settings |
| `k8s_service_host` | EKS API endpoint (https stripped) | Required for kubeProxyReplacement |
| `k8s_service_port` | `"443"` | |
| `helm_chart_version` | Pinned in `_versions.hcl` | Currently 1.19.4 |
| `helm_wait` | `false` | Does not block — nodes aren't up yet |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
