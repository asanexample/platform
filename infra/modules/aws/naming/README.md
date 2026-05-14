# AWS Naming Module

Generates standardized, convention-aligned resource names for AWS infrastructure. Follows the same naming pattern as the Azure CAF naming module adapted for AWS resource constraints.

## Naming Pattern

- Standard resources: `{type}-{workload}-{env}-{region}`
- Tight-constraint resources (S3, ECR): `{type}{abbreviated_workload}{env}{region}`
- CloudWatch Log Groups: `/{type}/{workload}/{env}/{region}`

## Usage

```hcl
module "naming" {
  source = "../../modules/aws/naming"

  workload    = "platform"
  environment = "prod"
  region_abbv = "use1"
  unique_seed = "my-unique-seed"  # optional, used for S3 bucket uniqueness
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = module.naming.vpc  # "vpc-platform-prod-use1"
  }
}

resource "aws_s3_bucket" "data" {
  bucket = module.naming.s3  # "s3platproduse1a1b2c3"
}

resource "aws_eks_cluster" "main" {
  name = module.naming.eks  # "eks-platform-prod-use1"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| workload | Workload identifier (2-10 chars) | string | "platform" | no |
| environment | Environment (dev, preprod, prod, test, stg, ops) | string | - | yes |
| region_abbv | Abbreviated AWS region (e.g., use1, usw2) | string | - | yes |
| unique_seed | Seed for globally unique names (S3) | string | "" | no |

## Outputs

Individual outputs for each resource type (e.g., `vpc`, `s3`, `eks`), plus:

- `names` - Map of all generated resource names
- `resource_types` - Map of all resource type abbreviations
