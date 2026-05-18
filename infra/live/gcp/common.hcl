# Common variables shared across all regions and environments
# This file contains global configuration for the GCP side of the platform

locals {
  # Project variables
  workload = "platform"

  # Common tags (applied as GCP labels)
  tags = {
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
  }

  # Environment → GCP project mapping (safety validation)
  # Used by _base.hcl to verify env.hcl project_id matches the expected value.
  # Add new environments here as they are onboarded.
  environment_project_map = {
    "ops" = "innovation-ops-gcp"
    "dev" = "innovation-dev-gcp"
  }
}
