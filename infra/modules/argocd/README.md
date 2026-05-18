# ArgoCD Module

Deploys ArgoCD on a Kubernetes cluster via the official Helm chart.

## Usage

```hcl
module "argocd" {
  source = "../argocd"

  domain            = "argocd.ops.example.com"
  high_availability = true
  service_type      = "ClusterIP"
  insecure          = false
  chart_version     = "5.51.4"

  enable_dex           = true
  enable_notifications = true
}
```

## Examples

### Disabled (namespace-only, no Helm release)

```hcl
module "argocd" {
  source           = "../argocd"
  create_namespace = false
}
```

### Dev cluster (single replica, no HA)

```hcl
module "argocd" {
  source = "../argocd"

  domain            = "argocd.dev.example.com"
  high_availability = false
  service_type      = "LoadBalancer"
  insecure          = true
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.argocd](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.argocd](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [time_sleep.wait_for_crds](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| additional_set_values | Additional values to set on the Helm release | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>    type  = optional(string)<br/>  }))</pre> | `[]` | no |
| admin_password | The password to use for the admin user. If not set, a random password will be generated. | `string` | `""` | no |
| chart_version | The version of the ArgoCD Helm chart to deploy | `string` | `"5.51.4"` | no |
| create_namespace | Whether to create the ArgoCD namespace | `bool` | `true` | no |
| domain | The domain to use for ArgoCD | `string` | `""` | no |
| enable_dex | Whether to enable the Dex server for SSO | `bool` | `true` | no |
| enable_notifications | Whether to enable the ArgoCD notifications controller | `bool` | `true` | no |
| helm_timeout | Timeout for Helm operations in seconds | `number` | `1200` | no |
| high_availability | Whether to deploy ArgoCD in high availability mode | `bool` | `false` | no |
| insecure | Whether to run the ArgoCD server in insecure mode | `bool` | `false` | no |
| namespace | The namespace to deploy ArgoCD into | `string` | `"argocd"` | no |
| namespace_labels | Labels to apply to the ArgoCD namespace | `map(string)` | `{}` | no |
| release_name | The name of the Helm release | `string` | `"argocd"` | no |
| service_type | The Kubernetes service type to use for the ArgoCD server | `string` | `"ClusterIP"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| admin_password | The admin password for ArgoCD (only if explicitly set) |
| namespace | The namespace where ArgoCD is deployed |
| release_name | The name of the Helm release |
| release_status | The status of the Helm release |
| server_service_name | The name of the ArgoCD server service |
| version | The version of ArgoCD that was deployed |
<!-- END_TF_DOCS -->

## Dependencies

- Any Kubernetes cluster (`aks_core`, EKS, GKE, etc.) — the cluster must exist and be reachable.

## Notes

- Cloud-agnostic module; works on any Kubernetes cluster with a Helm and Kubernetes provider configured.
- If no `admin_password` is provided, ArgoCD generates a random one stored in the `argocd-initial-admin-secret` secret.
- A 120-second `time_sleep` follows the Helm release to let ArgoCD CRDs stabilize before downstream modules (like `argocd-bootstrap`) apply `Application` resources.
- The Helm release uses `atomic = true` — a failed deploy automatically rolls back.
