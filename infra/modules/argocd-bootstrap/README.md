# ArgoCD Bootstrap

Creates ArgoCD Application resources for bootstrapping core platform components (cert-manager, external-dns, external-secrets) via the App-of-Apps pattern. Each application is deployed with sync-wave ordering, automated sync with self-heal and prune, and namespace auto-creation. Applications are only created when the `bootstrap_applications` list is non-empty.

## Usage

```hcl
module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  argocd_namespace = "argocd"
  project          = "default"
  server           = "https://kubernetes.default.svc"

  bootstrap_applications = [
    {
      name            = "cert-manager"
      namespace       = "cert-manager"
      repo_url        = "https://charts.jetstack.io"
      chart           = "cert-manager"
      target_revision = "v1.12.0"
      sync_wave       = 0
      helm_values     = { installCRDs = "true" }
    },
    {
      name            = "external-dns"
      namespace       = "external-dns"
      repo_url        = "https://kubernetes-sigs.github.io/external-dns"
      chart           = "external-dns"
      target_revision = "1.13.1"
      sync_wave       = 1
    },
  ]
}
```

## Examples

### Disabled (No Bootstrap Apps)

```hcl
module "argocd_bootstrap" {
  source = "../../modules/argocd-bootstrap"

  argocd_namespace       = "argocd"
  bootstrap_applications = []
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_manifest.cert_manager](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.external_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.external_secrets](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_argocd_namespace"></a> [argocd\_namespace](#input\_argocd\_namespace) | The namespace where ArgoCD is deployed | `string` | n/a | yes |
| <a name="input_bootstrap_applications"></a> [bootstrap\_applications](#input\_bootstrap\_applications) | List of applications to bootstrap with ArgoCD | <pre>list(object({<br/>    name            = string<br/>    namespace       = string<br/>    repo_url        = string<br/>    path            = optional(string, "")<br/>    chart           = optional(string, "")<br/>    target_revision = string<br/>    helm_values     = optional(map(string), {})<br/>    sync_wave       = optional(number, 0)<br/>    self_heal       = optional(bool, true)<br/>    prune           = optional(bool, true)<br/>  }))</pre> | `[]` | no |
| <a name="input_project"></a> [project](#input\_project) | The ArgoCD project to use for applications | `string` | `"default"` | no |
| <a name="input_server"></a> [server](#input\_server) | The Kubernetes server URL for ArgoCD to connect to | `string` | `"https://kubernetes.default.svc"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bootstrap_applications"></a> [bootstrap\_applications](#output\_bootstrap\_applications) | The list of bootstrap applications |
| <a name="output_bootstrap_applications_count"></a> [bootstrap\_applications\_count](#output\_bootstrap\_applications\_count) | The number of bootstrap applications configured |
| <a name="output_cert_manager_name"></a> [cert\_manager\_name](#output\_cert\_manager\_name) | The name of the cert-manager application |
| <a name="output_external_dns_name"></a> [external\_dns\_name](#output\_external\_dns\_name) | The name of the external-dns application |
| <a name="output_external_secrets_name"></a> [external\_secrets\_name](#output\_external\_secrets\_name) | The name of the external-secrets application |
<!-- END_TF_DOCS -->

## Notes

- The module hardcodes three Application resources (cert-manager, external-dns, external-secrets) regardless of the `bootstrap_applications` input. The variable controls whether they are created at all but does not dynamically generate applications from its contents.
- Sync-wave annotations control ordering: cert-manager at wave 0, external-dns and external-secrets at wave 1.
- All bootstrap applications use `CreateNamespace=true` so their target namespaces are created automatically.

## Related ADRs

- ADR-021: ArgoCD for GitOps Delivery
