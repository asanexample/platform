locals {
  # Config secrets (ADR-066) — TG_SOPS_BOOTSTRAP=1 falls back to plaintext secrets.hcl for greenfield. See common.hcl.
  _secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1" ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))

  env           = "preprod"
  environment   = "preprod"
  workload      = "platform"
  account_alias = "preprod-aws"
  account_id    = local._secrets.account_ids["preprod"]

  # Zero-code instrumentation (P7 / #586): run Beyla on preprod so its workloads emit RED metrics + traces
  # with no app changes. Traces -> the preprod traces-spoke collector -> hub Tempo (tenant preprod); RED
  # metrics -> Beyla's ServiceMonitor -> the preprod metrics agent -> hub Mimir (tenant preprod).
  enable_instrumentation = true

  # Cost metrics (ADR-091): run OpenCost on preprod so tenant-environment cost (alpha/bravo) is measured where
  # the workloads run. Its exporter metrics -> the spoke prometheus-agent -> hub Mimir (tenant preprod); the hub
  # cost dashboard's federated `mimir-all` datasource renders them. (Cost overrides the dev profile's default.)
  enable_cost_metrics = true

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
