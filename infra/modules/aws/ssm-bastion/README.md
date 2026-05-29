# SSM Bastion

Deploys a lightweight EC2 instance in a private subnet for use as an SSM Session Manager bastion host. The instance has no inbound security group rules (access is exclusively through SSM), uses Amazon Linux 2023 with IMDSv2 required, and has an encrypted root volume. When an EKS cluster security group ID is provided, the module adds an ingress rule allowing HTTPS (port 443) from the bastion to the cluster API server, enabling `kubectl` access through SSM port forwarding.

## Usage

```hcl
module "ssm_bastion" {
  source = "../../modules/aws/ssm-bastion"

  name      = "platform-use1-bastion"
  vpc_id    = module.networking.vpc_id
  subnet_id = module.networking.subnet_ids["snet-platform-ops-private-use1-a-kubernetes"]

  cluster_security_group_id = module.eks.cluster_security_group_id

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "ssm_bastion" {
  source = "../../modules/aws/ssm-bastion"
  create = false

  name      = "unused"
  vpc_id    = "vpc-xxx"
  subnet_id = "subnet-xxx"
}
```

### Bastion Without EKS Access

```hcl
module "ssm_bastion" {
  source = "../../modules/aws/ssm-bastion"

  name          = "debug-bastion"
  vpc_id        = module.networking.vpc_id
  subnet_id     = module.networking.subnet_ids["private-a"]
  instance_type = "t3.micro"

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
| <a name="input_name"></a> [name](#input\_name) | Name prefix for all resources | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Private subnet ID for the bastion instance | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to place the bastion in | `string` | n/a | yes |
| <a name="input_cluster_security_group_id"></a> [cluster\_security\_group\_id](#input\_cluster\_security\_group\_id) | EKS cluster security group ID — when set, adds an ingress rule allowing HTTPS from the bastion | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type | `string` | `"t3.nano"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | EC2 instance ID for SSM session targets |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID of the bastion |
<!-- END_TF_DOCS -->

## Notes

- The bastion AMI is automatically resolved to the latest Amazon Linux 2023 x86_64 AMI via SSM Parameter Store.
- The security group only allows HTTPS egress (port 443), which is sufficient for SSM agent communication and EKS API access.
- Default instance type is `t3.nano`, the smallest general-purpose instance, since the bastion only serves as an SSM relay.
- The EKS cluster security group ingress rule is only created when `cluster_security_group_id` is set.
