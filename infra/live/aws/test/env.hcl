locals {
  _secrets = read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl")

  env           = "test"
  environment   = "test"
  workload      = "test"
  account_alias = "test-aws"
  account_id    = local._secrets.locals.account_ids["test"]

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
