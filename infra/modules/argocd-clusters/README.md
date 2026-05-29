# ArgoCD Clusters

Registers remote Kubernetes clusters with ArgoCD by creating labeled Kubernetes Secrets in the ArgoCD namespace. Each secret contains the cluster name, API server URL, CA data, and optional AWS IAM auth configuration for cross-account EKS access. ArgoCD discovers these secrets via the `argocd.argoproj.io/secret-type: cluster` label.

## Usage

```hcl
module "argocd_clusters" {
  source = "../../modules/argocd-clusters"

  namespace = "argocd"

  clusters = {
    preprod = {
      server  = "https://EXAMPLE.gr7.us-east-1.eks.amazonaws.com"
      ca_data = base64encode(file("preprod-ca.pem"))
      aws_auth = {
        cluster_name = "preprod-use1-eks"
        role_arn     = "arn:aws:iam::<PREPROD_ACCOUNT_ID>:role/PlatformDeployer"
      }
    }
  }
}
```

## Examples

### Disabled Module

```hcl
module "argocd_clusters" {
  source = "../../modules/argocd-clusters"

  create = false
}
```

### Non-AWS Cluster (No IAM Auth)

```hcl
module "argocd_clusters" {
  source = "../../modules/argocd-clusters"

  clusters = {
    staging = {
      server   = "https://staging-aks.westus2.azmk8s.io:443"
      ca_data  = base64encode(file("staging-ca.pem"))
      aws_auth = null
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.35.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.35.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_secret_v1.cluster](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_clusters"></a> [clusters](#input\_clusters) | Map of remote clusters to register with ArgoCD | <pre>map(object({<br/>    server  = string<br/>    ca_data = string<br/>    aws_auth = optional(object({<br/>      cluster_name = string<br/>      role_arn     = string<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ArgoCD namespace where cluster secrets are created | `string` | `"argocd"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_names"></a> [cluster\_names](#output\_cluster\_names) | Names of registered remote clusters |
<!-- END_TF_DOCS -->

## Notes

- The `aws_auth` field is optional. When set, ArgoCD uses `awsAuthConfig` to assume the specified IAM role for cluster authentication. When `null`, only TLS CA data is used.
- Cluster secrets are created in the ArgoCD namespace (default `argocd`). ArgoCD must be installed before this module is applied.
- The secret `config` field is JSON-encoded and contains `tlsClientConfig.caData` plus optional `awsAuthConfig`.

## Related ADRs

- ADR-021: ArgoCD for GitOps Delivery
