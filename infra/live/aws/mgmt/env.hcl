locals {
  _secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))

  env           = "mgmt"
  environment   = "mgmt"
  workload      = "management"
  account_alias = "management-aws"
  account_id    = local._secrets.account_ids["mgmt"]

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
