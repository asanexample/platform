locals {
  # Config secrets (ADR-066) — TG_SOPS_BOOTSTRAP=1 falls back to plaintext secrets.hcl for greenfield. See common.hcl.
  _secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1" ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))

  env           = "test"
  environment   = "test"
  workload      = "test"
  account_alias = "test-aws"
  account_id    = local._secrets.account_ids["test"]

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
