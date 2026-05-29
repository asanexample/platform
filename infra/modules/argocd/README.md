# ArgoCD

Deploys ArgoCD via Helm with optional IRSA (IAM Roles for Service Accounts) on AWS EKS. Creates the ArgoCD Helm release with configurable HA replicas, RBAC policies, Dex SSO, ApplicationSet controller, and notifications. When IRSA is enabled, provisions an IAM role with ECR read-only access and optional cross-account `sts:AssumeRole` permissions for managing remote clusters. The IRSA role is annotated on the controller, server, and repo-server service accounts. Tags are converted to Kubernetes-safe pod labels. CiliumIdentity resources are excluded from ArgoCD management by default.

## Usage

```hcl
module "argocd" {
  source = "../../modules/argocd"

  cluster_name      = "platform-use1-eks"
  oidc_provider_arn = "arn:aws:iam::829808296602:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  oidc_provider_url = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"

  high_availability = true
  dex_enabled       = true
  rbac_scopes       = "[groups]"

  remote_cluster_role_arns = [
    "arn:aws:iam::620830101009:role/PlatformDeployer",
  ]

  argocd_cm_extra = {
    "dex.config" = yamlencode({
      connectors = [{
        type = "saml"
        id   = "aws-sso"
        name = "AWS SSO"
        config = {
          ssoURL      = "https://portal.sso.us-east-1.amazonaws.com/saml/..."
          caData      = "base64-cert-data"
          redirectURI = "https://argocd.aws.refplat.org/api/dex/callback"
        }
      }]
    })
  }

  tags = {
    Environment = "platform"
    ManagedBy   = "terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "argocd" {
  source = "../../modules/argocd"

  create       = false
  cluster_name = "platform-use1-eks"
}
```

### Minimal (No IRSA)

```hcl
module "argocd" {
  source = "../../modules/argocd"

  cluster_name = "platform-use1-eks"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.argocd](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.remote_clusters](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ecr_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [helm_release.argocd](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_iam_policy_document.argocd_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster (used for IAM role naming) | `string` | n/a | yes |
| <a name="input_applicationset_enabled"></a> [applicationset\_enabled](#input\_applicationset\_enabled) | Enable ApplicationSet controller | `bool` | `true` | no |
| <a name="input_argocd_cm_extra"></a> [argocd\_cm\_extra](#input\_argocd\_cm\_extra) | Additional key-value pairs to merge into argocd-cm ConfigMap | `map(string)` | `{}` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether ArgoCD resources should be created | `bool` | `true` | no |
| <a name="input_credential_templates"></a> [credential\_templates](#input\_credential\_templates) | Credential templates for repo pattern matching | `any` | `{}` | no |
| <a name="input_dex_enabled"></a> [dex\_enabled](#input\_dex\_enabled) | Enable Dex SSO server | `bool` | `false` | no |
| <a name="input_extra_iam_policy_arns"></a> [extra\_iam\_policy\_arns](#input\_extra\_iam\_policy\_arns) | Additional IAM policy ARNs to attach to the ArgoCD IRSA role | `list(string)` | `[]` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Name of the Helm chart | `string` | `"argo-cd"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Version of the ArgoCD Helm chart | `string` | `"9.5.14"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Name of the Helm release | `string` | `"argocd"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Repository URL for the ArgoCD Helm chart | `string` | `"https://argoproj.github.io/argo-helm"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds | `number` | `900` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Whether to wait for Helm release to complete | `bool` | `true` | no |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | Deploy ArgoCD in HA mode (2 replicas per component) | `bool` | `false` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to install ArgoCD into | `string` | `"argocd"` | no |
| <a name="input_notifications_enabled"></a> [notifications\_enabled](#input\_notifications\_enabled) | Enable ArgoCD notifications controller | `bool` | `false` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the EKS OIDC provider for IRSA. Empty string disables IRSA. | `string` | `""` | no |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | OIDC provider URL (without https:// prefix) for IRSA trust policy | `string` | `""` | no |
| <a name="input_projects"></a> [projects](#input\_projects) | ArgoCD project definitions | `any` | `{}` | no |
| <a name="input_rbac_default_policy"></a> [rbac\_default\_policy](#input\_rbac\_default\_policy) | Default RBAC policy (role:readonly, role:admin, or empty) | `string` | `"role:readonly"` | no |
| <a name="input_rbac_policy_csv"></a> [rbac\_policy\_csv](#input\_rbac\_policy\_csv) | RBAC policy rules in ArgoCD CSV format | `string` | `"p, role:org-admin, applications, *, */*, allow\np, role:org-admin, clusters, get, *, allow\np, role:org-admin, repositories, *, *, allow\np, role:org-admin, logs, get, *, allow\np, role:org-admin, exec, create, */*, allow\ng, org-admin, role:org-admin\n"` | no |
| <a name="input_rbac_scopes"></a> [rbac\_scopes](#input\_rbac\_scopes) | OIDC scopes to inspect for RBAC (e.g., '[groups]' for Dex group claims) | `string` | `""` | no |
| <a name="input_reconciliation_timeout"></a> [reconciliation\_timeout](#input\_reconciliation\_timeout) | How often ArgoCD re-syncs applications | `string` | `"180s"` | no |
| <a name="input_remote_cluster_role_arns"></a> [remote\_cluster\_role\_arns](#input\_remote\_cluster\_role\_arns) | Cross-account IAM role ARNs that ArgoCD needs to assume for remote cluster management | `list(string)` | `[]` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Repository credentials for ArgoCD (map of repo objects) | `any` | `{}` | no |
| <a name="input_resource_exclusions"></a> [resource\_exclusions](#input\_resource\_exclusions) | Resources ArgoCD should ignore (list of {apiGroups, kinds, clusters}) | `any` | <pre>[<br/>  {<br/>    "apiGroups": [<br/>      "cilium.io"<br/>    ],<br/>    "clusters": [<br/>      "*"<br/>    ],<br/>    "kinds": [<br/>      "CiliumIdentity"<br/>    ]<br/>  }<br/>]</pre> | no |
| <a name="input_server_insecure"></a> [server\_insecure](#input\_server\_insecure) | Run ArgoCD server without TLS (for use behind a TLS-terminating proxy or port-forward) | `bool` | `true` | no |
| <a name="input_server_service_type"></a> [server\_service\_type](#input\_server\_service\_type) | Kubernetes service type for the ArgoCD server | `string` | `"ClusterIP"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_helm_release_name"></a> [helm\_release\_name](#output\_helm\_release\_name) | Name of the ArgoCD Helm release |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the ArgoCD Helm release |
| <a name="output_helm_release_version"></a> [helm\_release\_version](#output\_helm\_release\_version) | Version of the ArgoCD Helm chart deployed |
| <a name="output_irsa_role_arn"></a> [irsa\_role\_arn](#output\_irsa\_role\_arn) | ARN of the IRSA IAM role for ArgoCD service accounts |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace where ArgoCD is installed |
<!-- END_TF_DOCS -->

## Notes

- IRSA is enabled automatically when `oidc_provider_arn` is non-empty. Setting it to `""` disables IAM role creation.
- The module uses `replace = true` on the Helm release, so failed installs are replaced rather than upgraded in-place.
- SSO configuration (Dex/SAML) is injected via `argocd_cm_extra` to keep the module cloud-agnostic -- the SAML app in Identity Center must be created manually.
- A `configHash` value forces Helm to detect config drift even when values don't change structurally.

## Related ADRs

- ADR-021: ArgoCD for GitOps Delivery
- ADR-012: ArgoCD SSO via Dex and SAML
