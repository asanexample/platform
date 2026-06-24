# EKS Add-ons

Installs EKS managed add-ons (such as CoreDNS, kube-proxy, and AWS EBS CSI driver) with optional IRSA (IAM Roles for Service Accounts) configuration per add-on. This module is separated from the EKS cluster module because with BYOCNI, addon pods (especially CoreDNS) cannot schedule until the CNI and node groups are ready. Each add-on can have its own IAM role with scoped trust policy and attached managed policies.

## Usage

```hcl
module "eks_addons" {
  source = "../../modules/aws/eks-addons"

  cluster_name      = "platform-use1-eks"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  addons = {
    coredns = {
      addon_version = "v1.11.4-eksbuild.2"
    }
    aws-ebs-csi-driver = {
      addon_version = "v1.37.0-eksbuild.1"
      irsa = {
        service_account_name      = "ebs-csi-controller-sa"
        service_account_namespace = "kube-system"
        policy_arns               = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
      }
    }
  }

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "eks_addons" {
  source = "../../modules/aws/eks-addons"
  create = false

  cluster_name = "unused"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_iam_role.addon](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.addon](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.addon_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster | `string` | n/a | yes |
| <a name="input_addons"></a> [addons](#input\_addons) | Map of EKS managed add-ons to install. Key is addon name, value is config. | <pre>map(object({<br/>    addon_version            = optional(string)<br/>    configuration_values     = optional(string)<br/>    service_account_role_arn = optional(string)<br/>    irsa = optional(object({<br/>      service_account_name      = string<br/>      service_account_namespace = string<br/>      policy_arns               = list(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources | `bool` | `true` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the EKS OIDC provider (required for addons that use IRSA) | `string` | `""` | no |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | URL of the EKS OIDC provider without https:// prefix | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_addons"></a> [addons](#output\_addons) | Map of installed addon names to their status |
<!-- END_TF_DOCS -->

## Notes

- This module must be deployed after Cilium and node groups are ready, since addon pods need the CNI to schedule.
- IRSA roles are only created when `oidc_provider_arn` is provided and the add-on has an `irsa` block.
- Conflict resolution is set to `OVERWRITE` for both create and update operations.
- You can provide a pre-existing IAM role via `service_account_role_arn` instead of using the built-in IRSA configuration.

## Related ADRs

- ADR-009: EKS Component Separation
