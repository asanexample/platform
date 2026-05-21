# Common variables shared across all regions and environments
# This file contains global configuration for the AWS platform

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

  # External DNS delegation
  cloudflare_zone_id = "373f3d8528f115c9583798ec11b6ed1e"

  # Azure global configuration (not applicable for AWS)
  azure_config = {}

  # Environment -> AWS account ID mapping (safety validation)
  # Used by _base.hcl to verify env.hcl account_id matches the expected value.
  # Add new environments here as they are onboarded.
  environment_account_map = {
    "platform" = "829808296602"
    "mgmt"     = "851725353202"
    "test"     = "157263244316"
    "preprod"  = "620830101009"
    "prod"     = "554518885123"
  }
}
