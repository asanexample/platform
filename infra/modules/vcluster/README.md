# vCluster

Deploys a vCluster (virtual Kubernetes cluster) instance on a host cluster via Helm. Creates a dedicated namespace with platform labels, configures the vCluster control plane with optional persistence, resource limits, and resource sync rules. Supports syncing ingresses, storage classes, nodes, and custom resources between the virtual and host clusters. Built-in policies for resource quotas, limit ranges, and network policies can be toggled individually.

**Note:** vCluster mode is currently deferred (ADR-033) because OSS vCluster cannot sync HTTPRoute CRDs to the host cluster's Gateway. The `tenant` module defaults all teams to `namespace` mode instead.

## Usage

```hcl
module "vcluster" {
  source = "../../modules/vcluster"

  cluster_name = "team-isolated"
  namespace    = "vc-isolated"
  environment  = "preprod"
  region_abbv  = "use1"

  chart_version       = "0.34.1"
  persistence_enabled = true
  storage_class       = "gp3"

  resource_limits = {
    cpu    = "2"
    memory = "4Gi"
  }

  policies = {
    network_policy = true
    limit_range    = true
    resource_quota = true
  }

  tags = {
    Environment = "preprod"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "vcluster" {
  source = "../../modules/vcluster"

  create       = false
  cluster_name = "team-isolated"
  namespace    = "vc-isolated"
  environment  = "preprod"
  region_abbv  = "use1"
}
```

### With Custom Resource Sync

```hcl
module "vcluster" {
  source = "../../modules/vcluster"

  cluster_name = "team-isolated"
  namespace    = "vc-isolated"
  environment  = "preprod"
  region_abbv  = "use1"

  custom_resource_sync = [
    {
      group   = "gateway.networking.k8s.io"
      version = "v1"
      plural  = "httproutes"
    },
  ]
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.10.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.10.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.vcluster](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.vcluster](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name for the vCluster instance | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., dev, preprod, prod) | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Host cluster namespace to deploy the vCluster into | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviated name of the region (e.g., wus for westus, eus for eastus) | `string` | n/a | yes |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the vCluster Helm chart | `string` | `"0.34.1"` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether vCluster resources should be created | `bool` | `true` | no |
| <a name="input_custom_resource_sync"></a> [custom\_resource\_sync](#input\_custom\_resource\_sync) | Custom resources to sync from virtual to host cluster (plural.apiGroup format) | <pre>list(object({<br/>    group   = string<br/>    version = string<br/>    plural  = string<br/>  }))</pre> | `[]` | no |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | Ingress configuration for vCluster API server exposure | <pre>object({<br/>    enabled       = optional(bool, false)<br/>    host          = optional(string, "")<br/>    ingress_class = optional(string, "")<br/>    tls_secret    = optional(string, "")<br/>  })</pre> | `null` | no |
| <a name="input_persistence_enabled"></a> [persistence\_enabled](#input\_persistence\_enabled) | Enable persistent volume for vCluster data (requires a working StorageClass + CSI driver) | `bool` | `true` | no |
| <a name="input_policies"></a> [policies](#input\_policies) | Policy enforcement for the vCluster deployment | <pre>object({<br/>    network_policy = optional(bool, true)<br/>    limit_range    = optional(bool, true)<br/>    resource_quota = optional(bool, true)<br/>  })</pre> | `{}` | no |
| <a name="input_resource_limits"></a> [resource\_limits](#input\_resource\_limits) | Resource limits for the vCluster control plane container | <pre>object({<br/>    cpu    = string<br/>    memory = string<br/>  })</pre> | `null` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for vCluster persistent volume | `string` | `null` | no |
| <a name="input_sync"></a> [sync](#input\_sync) | Sync configuration for vCluster (controls which resources are synced between host and virtual cluster) | <pre>object({<br/>    nodes           = optional(bool, false)<br/>    ingresses       = optional(bool, false)<br/>    storage_classes = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_values"></a> [values](#input\_values) | Custom Helm values YAML to pass to the vCluster chart | `string` | `""` | no |
| <a name="input_vcluster_version"></a> [vcluster\_version](#input\_vcluster\_version) | vCluster application version | `string` | `"0.34.1"` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource naming | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_helm_release_name"></a> [helm\_release\_name](#output\_helm\_release\_name) | Name of the vCluster Helm release |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the vCluster Helm release |
| <a name="output_kubeconfig_secret_name"></a> [kubeconfig\_secret\_name](#output\_kubeconfig\_secret\_name) | Name of the K8s secret containing the vCluster kubeconfig |
| <a name="output_name"></a> [name](#output\_name) | Name of the vCluster instance |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where the vCluster is deployed |
<!-- END_TF_DOCS -->

## Notes

- The module creates its own namespace (`kubernetes_namespace`) and sets `create_namespace = false` on the Helm release to ensure proper label management.
- The kubeconfig for the virtual cluster is stored in a Kubernetes secret named `vc-<cluster_name>` in the vCluster namespace.
- Persistence is enabled by default. Set `persistence_enabled = false` for ephemeral clusters, but note that data is lost on pod restart.
- This module is typically invoked indirectly via the `tenant` module when a tenant's `mode` is set to `"vcluster"`.

## Related ADRs

- ADR-027: Hybrid Tenant Isolation Model
- ADR-033: Defer vCluster Tenant Support
