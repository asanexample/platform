locals {
  _secrets = read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl")

  env           = "prod"
  environment   = "prod"
  workload      = "platform"
  account_alias = "prod-aws"
  account_id    = local._secrets.locals.account_ids["prod"]

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
