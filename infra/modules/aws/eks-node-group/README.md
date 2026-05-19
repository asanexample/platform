# EKS Node Group

Creates EKS managed node groups with a shared IAM node role (EKSWorkerNode, ECR read-only, SSM policies).

## Usage

```hcl
module "eks_nodes" {
  source = "../../modules/aws/eks-node-group"

  create = true

  # Required
  cluster_name = "platform-use1-eks"

  # Optional
  node_groups = {
    system = {
      subnet_ids     = ["subnet-abc123", "subnet-def456"]
      instance_types = ["m6i.large"]
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      capacity_type  = "ON_DEMAND"
      labels         = { role = "system" }
    }
  }

  tags = {
    Environment = "platform"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled module

```hcl
module "eks_nodes" {
  source = "../../modules/aws/eks-node-group"
  create = false
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
| [aws_eks_node_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.node_ecr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster to attach node groups to | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | Managed node group definitions | <pre>map(object({<br/>    subnet_ids      = list(string)<br/>    instance_types  = list(string)<br/>    desired_size    = number<br/>    max_size        = number<br/>    min_size        = number<br/>    capacity_type   = optional(string, "ON_DEMAND")<br/>    ami_type        = optional(string, "AL2023_x86_64_STANDARD")<br/>    max_unavailable = optional(number, 1)<br/>    labels          = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_node_group_names"></a> [node\_group\_names](#output\_node\_group\_names) | Map of node group names to their status |
| <a name="output_node_role_arn"></a> [node\_role\_arn](#output\_node\_role\_arn) | The ARN of the IAM role used by node groups |
<!-- END_TF_DOCS -->

## Dependencies

- [eks](../eks) -- needs `cluster_name` from the EKS cluster module

## Notes

- Separated from the EKS cluster module so node groups can depend on Cilium CNI being deployed first. Nodes that join before the CNI is running will fail to become Ready.
