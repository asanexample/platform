# EKS Node Group

Creates EKS managed node groups with a shared IAM node role. The node role includes the standard EKS worker, ECR read-only, SSM managed instance, and CNI policies. Each node group is independently configurable for instance types, scaling parameters, capacity type (on-demand vs spot), AMI type, and Kubernetes labels. Node groups are separated from the EKS module to enforce deployment ordering -- Cilium must be deployed before nodes can join the cluster.

## Usage

```hcl
module "node_groups" {
  source = "../../modules/aws/eks-node-group"

  cluster_name = "platform-use1-eks"

  node_groups = {
    general = {
      subnet_ids     = ["subnet-aaa", "subnet-bbb"]
      instance_types = ["m7i.large"]
      desired_size   = 3
      max_size       = 5
      min_size       = 2
      labels = {
        role = "general"
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
module "node_groups" {
  source = "../../modules/aws/eks-node-group"
  create = false

  cluster_name = "unused"
}
```

### Mixed On-Demand and Spot Groups

```hcl
module "node_groups" {
  source = "../../modules/aws/eks-node-group"

  cluster_name = "preprod-use1-eks"

  node_groups = {
    system = {
      subnet_ids     = ["subnet-aaa", "subnet-bbb"]
      instance_types = ["m7i.large"]
      desired_size   = 2
      max_size       = 3
      min_size       = 2
      capacity_type  = "ON_DEMAND"
      labels         = { role = "system" }
    }
    workloads = {
      subnet_ids     = ["subnet-aaa", "subnet-bbb"]
      instance_types = ["m7i.large", "m6i.large"]
      desired_size   = 2
      max_size       = 10
      min_size       = 0
      capacity_type  = "SPOT"
      labels         = { role = "workloads" }
    }
  }

  tags = {
    Environment = "preprod"
  }
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
| [aws_iam_role_policy_attachment.node_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
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

## Notes

- A single IAM node role is shared across all node groups in the module. The role includes `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore`, and `AmazonEKS_CNI_Policy`.
- The default AMI type is `AL2023_x86_64_STANDARD` (Amazon Linux 2023).
- This module must be deployed after Cilium is installed, since nodes will fail to join the cluster without a CNI.
- No resources are created if `node_groups` is empty, even when `create = true`.
