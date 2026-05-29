# ArgoCD Apps

Creates ArgoCD AppProjects, Applications, and ApplicationSets for multi-tenant workload deployment. Each tenant gets an AppProject scoped to its namespace and permitted resource types. Each app within a tenant gets a stable Application using Kustomize with `commonLabels` to avoid label selector collisions. Apps with `preview = true` get an additional ApplicationSet using the GitHub PR generator for ephemeral per-PR deployments, with automatic hostname rewriting and ECR image tag injection based on the PR head SHA.

## Usage

```hcl
module "argocd_apps" {
  source = "../../modules/argocd-apps"

  cluster_name   = "preprod"
  cluster_server = "https://EXAMPLE.gr7.us-east-1.eks.amazonaws.com"

  github_org               = "centric"
  ecr_registry             = "829808296602.dkr.ecr.us-east-1.amazonaws.com"
  preview_domain           = "preprod.aws.refplat.org"
  github_token_secret_name = "github-pat"

  tenants = {
    acme = {
      mode = "namespace"
      apps = {
        web = {
          repo_url = "https://github.com/centric/acme-web"
          preview  = true
        }
        api = {
          repo_url    = "https://github.com/centric/acme-api"
          repo_path   = "k8s/preprod"
          repo_branch = "main"
        }
      }
    }
  }
}
```

## Examples

### Disabled Module

```hcl
module "argocd_apps" {
  source = "../../modules/argocd-apps"

  create       = false
  cluster_name = "preprod"
}
```

### Manual Sync (No Auto-Sync)

```hcl
module "argocd_apps" {
  source = "../../modules/argocd-apps"

  cluster_name   = "preprod"
  cluster_server = "https://EXAMPLE.gr7.us-east-1.eks.amazonaws.com"
  auto_sync      = false

  tenants = {
    acme = {
      apps = {
        web = {
          repo_url = "https://github.com/centric/acme-web"
        }
      }
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_manifest.app_project](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.application](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.preview_appset](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the target cluster in ArgoCD (e.g. 'preprod') | `string` | n/a | yes |
| <a name="input_argocd_namespace"></a> [argocd\_namespace](#input\_argocd\_namespace) | Namespace where ArgoCD is installed | `string` | `"argocd"` | no |
| <a name="input_auto_sync"></a> [auto\_sync](#input\_auto\_sync) | Enable automated sync with self-heal and prune | `bool` | `true` | no |
| <a name="input_cluster_server"></a> [cluster\_server](#input\_cluster\_server) | API server URL of the target cluster | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create ArgoCD app resources | `bool` | `true` | no |
| <a name="input_ecr_registry"></a> [ecr\_registry](#input\_ecr\_registry) | ECR registry URL (e.g. 829808296602.dkr.ecr.us-east-1.amazonaws.com) | `string` | `""` | no |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | GitHub org for PR preview generators | `string` | `""` | no |
| <a name="input_github_token_secret_name"></a> [github\_token\_secret\_name](#input\_github\_token\_secret\_name) | Name of the Kubernetes Secret in the ArgoCD namespace containing the GitHub PAT (key: token) | `string` | `""` | no |
| <a name="input_preview_domain"></a> [preview\_domain](#input\_preview\_domain) | Base domain for PR preview hostnames (e.g. preprod.aws.refplat.org) | `string` | `""` | no |
| <a name="input_tenants"></a> [tenants](#input\_tenants) | Map of tenant names to their apps and isolation mode | <pre>map(object({<br/>    mode      = optional(string, "namespace")<br/>    namespace = optional(string)<br/>    apps = map(object({<br/>      repo_url    = string<br/>      repo_path   = optional(string, "k8s/preprod")<br/>      repo_branch = optional(string, "main")<br/>      preview     = optional(bool, false)<br/>    }))<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_projects"></a> [app\_projects](#output\_app\_projects) | Map of tenant names to their ArgoCD AppProject names |
| <a name="output_applications"></a> [applications](#output\_applications) | Map of app keys to their ArgoCD Application names |
| <a name="output_preview_appsets"></a> [preview\_appsets](#output\_preview\_appsets) | Map of app keys to their ArgoCD ApplicationSet names (preview-enabled apps only) |
<!-- END_TF_DOCS -->

## Notes

- AppProject whitelists are restrictive by design: Deployments, StatefulSets, Services, ConfigMaps, Secrets, Jobs, CronJobs, HTTPRoutes, and ExternalSecrets.
- Preview ApplicationSets use Kustomize `namePrefix` (`pr-<number>-`) and `commonLabels` (`app.kubernetes.io/instance: pr-<number>`) to isolate preview pods from stable deployments.
- Preview hostname rewriting patches `HTTPRoute` hostnames to `<app>-pr-<number>.<preview_domain>`.
- The `github_org` variable must be set for PR preview generators to be created; if empty, preview ApplicationSets are skipped.

## Related ADRs

- ADR-031: Multi-App Tenant Model
- ADR-032: PR Preview Environments
