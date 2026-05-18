# Common variables shared across all regions and environments
# This file contains global configuration for the platform

locals {
  # Project variables
  workload = "platform"

  # Common tags
  tags = {
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
  }

  # Azure global configuration
  azure_config = {
    cli_default_timeout_minutes = 30
  }

  # Environment → subscription mapping (safety validation)
  # Used by _base.hcl to verify env.hcl subscription_id matches the expected value.
  # Add new environments here as they are onboarded.
  environment_subscription_map = {
    "dev" = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
    "ops" = "9dc5edc4-8c4e-41a1-a4f8-2183c4e91954"
  }
} 