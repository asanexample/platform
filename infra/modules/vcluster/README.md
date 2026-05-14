# vCluster Module

Deploys [vCluster](https://www.vcluster.com/) (virtual Kubernetes clusters) on a host cluster via Helm chart. vCluster creates lightweight, fully functional virtual clusters that run inside the namespaces of a host cluster, providing strong isolation without requiring separate infrastructure.

## Usage

### Basic deployment

```hcl
module "vcluster" {
  source = "../vcluster"

  cluster_name  = "vc-platform-dev-wus"
  namespace     = "vcluster-dev"
  environment   = "dev"
  region_abbv   = "wus"
  chart_version = "0.24.1"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

### Isolated deployment with network policies

```hcl
module "vcluster_isolated" {
  source = "../vcluster"

  cluster_name  = "vc-platform-prod-eus"
  namespace     = "vcluster-prod"
  environment   = "prod"
  region_abbv   = "eus"
  chart_version = "0.24.1"

  resource_limits = {
    cpu    = "1000m"
    memory = "1Gi"
  }

  isolation = {
    network_policy = true
    limit_range    = { enabled = true }
    resource_quota = { enabled = true }
  }

  sync = {
    nodes           = false
    ingresses       = true
    storage_classes = true
  }

  ingress = {
    enabled       = true
    host          = "vcluster-prod.example.com"
    ingress_class = "nginx"
    tls_secret    = "vcluster-tls"
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

### Disabled

```hcl
module "vcluster" {
  source       = "../vcluster"
  create       = false
  cluster_name = ""
  namespace    = ""
  environment  = "dev"
  region_abbv  = "wus"
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.vcluster](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.vcluster](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster_name | Name for the vCluster instance | `string` | n/a | yes |
| namespace | Host cluster namespace to deploy into | `string` | n/a | yes |
| environment | Environment name (e.g., dev, ops, prod) | `string` | n/a | yes |
| region_abbv | Abbreviated name of the region | `string` | n/a | yes |
| chart_version | Version of the vCluster Helm chart | `string` | `"0.24.1"` | no |
| create | Controls whether vCluster resources should be created | `bool` | `true` | no |
| ingress | Ingress configuration for vCluster API server | `object` | `null` | no |
| isolation | Isolation settings (network policy, limit range, resource quota) | `object` | `null` | no |
| resource_limits | Resource limits for the vCluster syncer | `object({cpu, memory})` | `null` | no |
| storage_class | Storage class for vCluster persistence | `string` | `null` | no |
| sync | Sync configuration (nodes, ingresses, storage_classes) | `object` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| values | Custom Helm values YAML | `string` | `""` | no |
| vcluster_version | vCluster application version | `string` | `"0.24.1"` | no |
| workload | Workload identifier for resource naming | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| name | Name of the vCluster instance |
| namespace | Kubernetes namespace where the vCluster is deployed |
| helm_release_name | Name of the vCluster Helm release |
| helm_release_status | Status of the vCluster Helm release |
<!-- END_TF_DOCS -->

## Dependencies

- A running Kubernetes host cluster must exist and be reachable before deploying vCluster.
- The `helm` and `kubernetes` providers must be configured in the calling module.

## Notes

- Cloud-agnostic module; works on any Kubernetes cluster (AKS, EKS, GKE, etc.).
- The Helm release uses `atomic = true` -- a failed deploy automatically rolls back.
- For advanced configuration beyond what the variables expose, use the `values` variable to pass raw Helm values YAML.
