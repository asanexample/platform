locals {
  # Config secrets (ADR-066) — TG_SOPS_BOOTSTRAP=1 falls back to plaintext secrets.hcl for greenfield. See common.hcl.
  _secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1" ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))

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
