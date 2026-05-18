# Common variables for ops environment across all regions
# This file contains all environment configuration that was previously split between common.hcl and env.hcl.
# For backward compatibility, a symbolic link from env.hcl to this file is created.

locals {
  # Environment variables
  env           = "ops"
  environment   = "ops"
  workload      = "platform"
  account_alias = "innovation-operations-aws"
  account_id    = "111111111111"

  # Common tags
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

  # Maintain env_tags for backward compatibility
  env_tags = {
    Environment        = local.environment
    AutoShutdown       = "True"
    DataClassification = "Internal"
    AccountAlias       = local.account_alias
  }
}
