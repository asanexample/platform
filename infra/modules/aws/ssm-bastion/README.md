# SSM Bastion

Creates an SSM Session Manager bastion for private EKS cluster access -- no SSH keys or inbound ports.

## Usage

```hcl
module "bastion" {
  source = "../../modules/aws/ssm-bastion"

  create = true

  # Required
  name      = "bastion-platform-use1"
  vpc_id    = module.networking.vpc_id
  subnet_id = module.networking.subnet_ids["az1-kubernetes"]

  # Optional
  instance_type             = "t3.nano"
  cluster_security_group_id = module.eks.cluster_security_group_id

  tags = {
    Environment = "platform"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled module

```hcl
module "bastion" {
  source = "../../modules/aws/ssm-bastion"
  create = false
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.45.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_instance_profile.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.eks_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_ssm_parameter.al2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_security_group_id"></a> [cluster\_security\_group\_id](#input\_cluster\_security\_group\_id) | EKS cluster security group ID — when set, adds an ingress rule allowing HTTPS from the bastion | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type | `string` | `"t3.nano"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for all resources | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Private subnet ID for the bastion instance | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to place the bastion in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | EC2 instance ID for SSM session targets |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID of the bastion |
<!-- END_TF_DOCS -->

## Dependencies

- Networking -- needs `vpc_id` and `subnet_id`
- [eks](../eks) -- optionally needs `cluster_security_group_id` to allow HTTPS from the bastion

## Notes

- Access is exclusively via SSM. There are no SSH keys, no inbound security group rules.
- Use with `scripts/eks-tunnel.sh` to tunnel kubectl through the bastion: `./scripts/eks-tunnel.sh <instance-id> <cluster-endpoint>`
- When `cluster_security_group_id` is set, the module adds an ingress rule to the EKS cluster security group allowing HTTPS (443) from the bastion.
