locals {
  # Config secrets (ADR-066) — TG_SOPS_BOOTSTRAP=1 falls back to plaintext secrets.hcl for greenfield. See common.hcl.
  _secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1" ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))

  env           = "prod"
  environment   = "prod"
  workload      = "platform"
  account_alias = "prod-aws"
  account_id    = local._secrets.account_ids["prod"]

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
