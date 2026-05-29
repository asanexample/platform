locals {
  _secrets = read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl")

  env           = "platform"
  environment   = "platform"
  workload      = "platform"
  account_alias = "platform-aws"
  account_id    = local._secrets.locals.account_ids["platform"]

  tags = {
    Environment        = local.environment
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
    AutoShutdown       = "True"
    AccountAlias       = local.account_alias
  }

  env_tags = {
    Environment        = local.environment
    AutoShutdown       = "True"
    DataClassification = "Internal"
    AccountAlias       = local.account_alias
  }
}
