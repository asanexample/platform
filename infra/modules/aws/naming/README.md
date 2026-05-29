# Naming

Generates standardized resource names for AWS infrastructure following a consistent `{type}-{workload}-{environment}-{region}` convention. Handles AWS-specific naming constraints such as character limits, allowed characters, and case requirements. For globally unique or length-constrained resources (S3, ECR, ALB, NLB), uses abbreviated forms with a deterministic unique suffix derived from an optional seed. Outputs individual names for each supported resource type plus subnet-specific variants.

## Usage

```hcl
module "naming" {
  source = "../../modules/aws/naming"

  workload    = "platform"
  environment = "ops"
  region_abbv = "use1"
  unique_seed = "<PLATFORM_ACCOUNT_ID>"
}

# Reference outputs:
# module.naming.eks       => "eks-platform-ops-use1"
# module.naming.vpc       => "vpc-platform-ops-use1"
# module.naming.s3        => "s3platopsuse1<hash>"
# module.naming.subnet_private => "snet-platform-ops-private-use1"
```

## Examples

### Preprod Environment

```hcl
module "naming" {
  source = "../../modules/aws/naming"

  workload    = "platform"
  environment = "preprod"
  region_abbv = "use1"
  unique_seed = "<PREPROD_ACCOUNT_ID>"
}
```

### Data Workload

```hcl
module "naming" {
  source = "../../modules/aws/naming"

  workload    = "data"
  environment = "prod"
  region_abbv = "usw2"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment (e.g., dev, preprod, prod, ops). | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | The abbreviated AWS region name (e.g., use1, usw2, euw1). | `string` | n/a | yes |
| <a name="input_unique_seed"></a> [unique\_seed](#input\_unique\_seed) | Seed for unique naming generation (used for globally unique resources like S3 buckets). | `string` | `""` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | The workload identifier used in resource naming (e.g., platform, data, hipaa, pci). | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb"></a> [alb](#output\_alb) | Standardized name for an Application Load Balancer. |
| <a name="output_cloudwatch_lg"></a> [cloudwatch\_lg](#output\_cloudwatch\_lg) | Standardized name for a CloudWatch Log Group. |
| <a name="output_dynamodb"></a> [dynamodb](#output\_dynamodb) | Standardized name for a DynamoDB table. |
| <a name="output_ecr"></a> [ecr](#output\_ecr) | Standardized name for an ECR repository. |
| <a name="output_efs"></a> [efs](#output\_efs) | Standardized name for an EFS filesystem. |
| <a name="output_eks"></a> [eks](#output\_eks) | Standardized name for an EKS cluster. |
| <a name="output_iam_policy"></a> [iam\_policy](#output\_iam\_policy) | Standardized name for an IAM policy. |
| <a name="output_iam_role"></a> [iam\_role](#output\_iam\_role) | Standardized name for an IAM role. |
| <a name="output_igw"></a> [igw](#output\_igw) | Standardized name for an Internet Gateway. |
| <a name="output_kms"></a> [kms](#output\_kms) | Standardized name for a KMS key. |
| <a name="output_lambda"></a> [lambda](#output\_lambda) | Standardized name for a Lambda function. |
| <a name="output_names"></a> [names](#output\_names) | Map of all generated resource names. |
| <a name="output_natgw"></a> [natgw](#output\_natgw) | Standardized name for a NAT Gateway. |
| <a name="output_nlb"></a> [nlb](#output\_nlb) | Standardized name for a Network Load Balancer. |
| <a name="output_rds"></a> [rds](#output\_rds) | Standardized name for an RDS instance. |
| <a name="output_resource_types"></a> [resource\_types](#output\_resource\_types) | All resource type abbreviations. |
| <a name="output_rtb"></a> [rtb](#output\_rtb) | Standardized name for a Route Table. |
| <a name="output_s3"></a> [s3](#output\_s3) | Standardized name for an S3 bucket (globally unique, lowercase). |
| <a name="output_secretsmanager"></a> [secretsmanager](#output\_secretsmanager) | Standardized name for a Secrets Manager secret. |
| <a name="output_sg"></a> [sg](#output\_sg) | Standardized name for a Security Group. |
| <a name="output_sns"></a> [sns](#output\_sns) | Standardized name for an SNS topic. |
| <a name="output_sqs"></a> [sqs](#output\_sqs) | Standardized name for an SQS queue. |
| <a name="output_subnet"></a> [subnet](#output\_subnet) | Base subnet name for generating type-specific subnet names. |
| <a name="output_subnet_data"></a> [subnet\_data](#output\_subnet\_data) | Standardized name for a data subnet. |
| <a name="output_subnet_intra"></a> [subnet\_intra](#output\_subnet\_intra) | Standardized name for an intra subnet (no internet access). |
| <a name="output_subnet_private"></a> [subnet\_private](#output\_subnet\_private) | Standardized name for a private subnet. |
| <a name="output_subnet_public"></a> [subnet\_public](#output\_subnet\_public) | Standardized name for a public subnet. |
| <a name="output_tg"></a> [tg](#output\_tg) | Standardized name for a Target Group. |
| <a name="output_vpc"></a> [vpc](#output\_vpc) | Standardized name for an AWS VPC. |
<!-- END_TF_DOCS -->

## Notes

- The `unique_seed` generates a 6-character MD5 hash suffix appended to globally unique resource names (S3 buckets). Using the AWS account ID as the seed is a common pattern.
- Workload names are abbreviated for tight-constraint resources: `platform` becomes `plat`, `connectivity` becomes `conn`, etc. Unknown workloads are truncated to 4 characters.
- Names are automatically truncated to AWS maximum lengths (e.g., 32 chars for ALB/NLB, 63 for S3, 64 for IAM roles).
- The `environment` variable is validated against a fixed list: `dev`, `preprod`, `prod`, `test`, `stg`, `ops`, `mgmt`.
- Supported resource types include: VPC, subnet, IGW, NAT GW, route table, security group, EKS, S3, ECR, ALB, NLB, target group, Lambda, RDS, DynamoDB, SQS, SNS, KMS, IAM role/policy, CloudWatch log group, EFS, and Secrets Manager.
