# EKS Pod Identity

Creates **EKS Pod Identity associations** binding `(cluster, namespace, serviceAccount)` to an IAM role.
Pods running as the named ServiceAccount receive the role's credentials via the EKS Pod Identity agent —
no `eks.amazonaws.com/role-arn` annotation, no OIDC trust juggling. The association is the *only* thing
that grants a pod its role, and it is an AWS-API resource environments cannot create, so it is the
platform-controlled, namespace+ServiceAccount-scoped isolation boundary (see ADR-041).

The module is team-agnostic: the per-environment `associations` map is assembled by the caller from the
git-native registries (`gitops/` — the Crossplane Environment Composition mints these per environment; the
old app-delivery `teams.hcl` is retired). The agent add-on (`eks-pod-identity-agent`) must be installed on the cluster (see the
`eks-addons` unit). Pair with the `iam_roles` module's `service` trust principal
(`pods.eks.amazonaws.com`) to create the role itself.

## Usage

```hcl
module "pod_identity" {
  source = "../../modules/aws/eks-pod-identity"

  cluster_name = "preprod-use1-eks"
  associations = {
    "alpha-shop-dev" = {
      namespace       = "alpha-shop-dev"   # the environment namespace: <team>-<product>-<stage>
      service_account = "shop-web"          # a named ServiceAccount (never "default")
      role_arn        = "arn:aws:iam::620830101009:role/Pod-team-alpha"
    }
  }
  tags = { Environment = "preprod" }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name the associations are created for | `string` | n/a | yes |
| <a name="input_associations"></a> [associations](#input\_associations) | Map of association key -> binding. Each binds a (namespace, service\_account) on the cluster to an IAM<br/>role; pods running as that ServiceAccount receive the role's credentials via the EKS Pod Identity<br/>agent. Team-agnostic: the per-environment map is built by the caller from the git-native registries (gitops/; teams.hcl retired). | <pre>map(object({<br/>    namespace       = string<br/>    service_account = string<br/>    role_arn        = string<br/>  }))</pre> | `{}` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the associations | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_association_arns"></a> [association\_arns](#output\_association\_arns) | Map of association key -> association ARN |
| <a name="output_association_ids"></a> [association\_ids](#output\_association\_ids) | Map of association key -> association ID |
<!-- END_TF_DOCS -->
