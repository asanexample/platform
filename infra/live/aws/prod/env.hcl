locals {
  env           = "prod"
  environment   = "prod"
  workload      = "platform"
  account_alias = "prod-aws"
  account_id    = "554518885123"

  tags = {
    Environment        = local.environment
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Confidential"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
    AutoShutdown       = "False"
    AccountAlias       = local.account_alias
  }

  env_tags = {
    Environment        = local.environment
    AutoShutdown       = "False"
    DataClassification = "Confidential"
    AccountAlias       = local.account_alias
  }
}
