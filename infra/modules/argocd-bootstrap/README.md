# ArgoCD Bootstrap Module

Deploys bootstrap ArgoCD Applications for foundational cluster services (cert-manager, external-dns, external-secrets).

## Usage

```hcl
module "argocd_bootstrap" {
  source = "../argocd-bootstrap"

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
      helm_values     = { "installCRDs" = "true" }
    },
    {
      name            = "external-dns"
      namespace       = "external-dns"
      repo_url        = "https://kubernetes-sigs.github.io/external-dns"
      chart           = "external-dns"
      target_revision = "1.13.1"
      sync_wave       = 1
    },
    {
      name            = "external-secrets"
      namespace       = "external-secrets"
      repo_url        = "https://charts.external-secrets.io"
      chart           = "external-secrets"
      target_revision = "0.9.5"
      sync_wave       = 1
    },
  ]
}
```

## Examples

### Disabled (no bootstrap apps)

```hcl
module "argocd_bootstrap" {
  source           = "../argocd-bootstrap"
  argocd_namespace = "argocd"
  bootstrap_applications = []
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_manifest.cert_manager](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.external_dns](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.external_secrets](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| argocd_namespace | The namespace where ArgoCD is deployed | `string` | n/a | yes |
| bootstrap_applications | List of applications to bootstrap with ArgoCD | <pre>list(object({<br/>    name            = string<br/>    namespace       = string<br/>    repo_url        = string<br/>    path            = optional(string, "")<br/>    chart           = optional(string, "")<br/>    target_revision = string<br/>    helm_values     = optional(map(string), {})<br/>    sync_wave       = optional(number, 0)<br/>    self_heal       = optional(bool, true)<br/>    prune           = optional(bool, true)<br/>  }))</pre> | `[]` | no |
| project | The ArgoCD project to use for applications | `string` | `"default"` | no |
| server | The Kubernetes server URL for ArgoCD to connect to | `string` | `"https://kubernetes.default.svc"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bootstrap_applications | The list of bootstrap applications |
| bootstrap_applications_count | The number of bootstrap applications configured |
| cert_manager_name | The name of the cert-manager application |
| external_dns_name | The name of the external-dns application |
| external_secrets_name | The name of the external-secrets application |
<!-- END_TF_DOCS -->

## Dependencies

- `argocd` — ArgoCD must be deployed and its CRDs available before this module runs.

## Notes

- Cloud-agnostic module; works on any cluster where ArgoCD is installed.
- Uses the App-of-Apps pattern: each entry in `bootstrap_applications` becomes a `kubernetes_manifest` of kind `Application` with automated sync (`selfHeal = true`, `prune = true`).
- `sync_wave` controls deployment ordering: lower values deploy first (e.g., cert-manager at wave 0 before external-dns at wave 1).
- All applications are configured with `CreateNamespace=true` so target namespaces are created automatically.
