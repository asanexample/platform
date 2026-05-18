locals {
  env               = "mgmt"
  environment       = "mgmt"
  workload          = "management"
  account_alias     = "management-aws"
  account_id        = "851725353202"

  tags = {
    Environment        = local.environment
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Confidential"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
    AccountAlias       = local.account_alias
  }

  env_tags = {
    Environment        = local.environment
    DataClassification = "Confidential"
    AccountAlias       = local.account_alias
  }
}
