locals {
  env           = "test"
  environment   = "test"
  workload      = "test"
  account_alias = "test-aws"
  account_id    = "157263244316"

  tags = {
    Environment        = local.environment
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
    AccountAlias       = local.account_alias
  }

  env_tags = {
    Environment        = local.environment
    DataClassification = "Internal"
    AccountAlias       = local.account_alias
  }
}
