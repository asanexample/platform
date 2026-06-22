locals {
  # Config secrets (ADR-066) — TG_SOPS_BOOTSTRAP=1 falls back to plaintext secrets.hcl for greenfield. See common.hcl.
  _secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1" ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))

  env           = "platform"
  environment   = "platform"
  workload      = "platform"
  account_alias = "platform-aws"
  account_id    = local._secrets.account_ids["platform"]

  # Cost-profile override: run Loki (logs — #102 P3a) on the platform dev cluster in cost-effective
  # single-binary mode, even though cost_profile=dev defaults durable stores off. (preprod stays off.)
  enable_loki           = true
  enable_log_pipeline   = true # Alloy DaemonSet → Loki (P3a). Pairs with enable_loki on the dev cluster.
  enable_tempo          = true # Tempo traces store (P3b).
  enable_trace_pipeline = true # OTel collector gateway → Tempo (P3b). Pairs with enable_tempo.
  enable_cloud_metrics  = true # YACE → Prometheus for AWS-resource metrics (P5b).
  enable_cost_metrics   = true # OpenCost → per-namespace/workload cost in Grafana (P11).

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
