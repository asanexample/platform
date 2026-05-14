output "vpc" {
  description = "Standardized name for an AWS VPC."
  value       = local.validated_names.vpc
}

output "subnet" {
  description = "Base subnet name for generating type-specific subnet names."
  value       = local.subnet_name
}

output "subnet_public" {
  description = "Standardized name for a public subnet."
  value       = local.subnet_public
}

output "subnet_private" {
  description = "Standardized name for a private subnet."
  value       = local.subnet_private
}

output "subnet_data" {
  description = "Standardized name for a data subnet."
  value       = local.subnet_data
}

output "subnet_intra" {
  description = "Standardized name for an intra subnet (no internet access)."
  value       = local.subnet_intra
}

output "igw" {
  description = "Standardized name for an Internet Gateway."
  value       = local.validated_names.igw
}

output "natgw" {
  description = "Standardized name for a NAT Gateway."
  value       = local.validated_names.natgw
}

output "rtb" {
  description = "Standardized name for a Route Table."
  value       = local.validated_names.rtb
}

output "sg" {
  description = "Standardized name for a Security Group."
  value       = local.validated_names.sg
}

output "eks" {
  description = "Standardized name for an EKS cluster."
  value       = local.validated_names.eks
}

output "s3" {
  description = "Standardized name for an S3 bucket (globally unique, lowercase)."
  value       = local.validated_names.s3
}

output "ecr" {
  description = "Standardized name for an ECR repository."
  value       = local.validated_names.ecr
}

output "alb" {
  description = "Standardized name for an Application Load Balancer."
  value       = local.validated_names.alb
}

output "nlb" {
  description = "Standardized name for a Network Load Balancer."
  value       = local.validated_names.nlb
}

output "tg" {
  description = "Standardized name for a Target Group."
  value       = local.validated_names.tg
}

output "lambda" {
  description = "Standardized name for a Lambda function."
  value       = local.validated_names.lambda
}

output "rds" {
  description = "Standardized name for an RDS instance."
  value       = local.validated_names.rds
}

output "dynamodb" {
  description = "Standardized name for a DynamoDB table."
  value       = local.validated_names.dynamodb
}

output "sqs" {
  description = "Standardized name for an SQS queue."
  value       = local.validated_names.sqs
}

output "sns" {
  description = "Standardized name for an SNS topic."
  value       = local.validated_names.sns
}

output "kms" {
  description = "Standardized name for a KMS key."
  value       = local.validated_names.kms
}

output "iam_role" {
  description = "Standardized name for an IAM role."
  value       = local.validated_names.iam_role
}

output "iam_policy" {
  description = "Standardized name for an IAM policy."
  value       = local.validated_names.iam_policy
}

output "cloudwatch_lg" {
  description = "Standardized name for a CloudWatch Log Group."
  value       = local.validated_names.cloudwatch_lg
}

output "efs" {
  description = "Standardized name for an EFS filesystem."
  value       = local.validated_names.efs
}

output "secretsmanager" {
  description = "Standardized name for a Secrets Manager secret."
  value       = local.validated_names.secretsmanager
}

output "resource_types" {
  description = "All resource type abbreviations."
  value       = local.resource_types
}

output "names" {
  description = "Map of all generated resource names."
  value       = local.validated_names
}
