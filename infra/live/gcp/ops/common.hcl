# Common variables for ops environment across all regions
# This file contains all environment configuration that was previously split between common.hcl and env.hcl.
# For backward compatibility, a symbolic link from env.hcl to this file is created.

locals {
  # Environment variables
  env         = "ops"
  environment = "ops"
  workload    = "platform"
  project_id  = "innovation-ops-gcp"

  # Common tags/labels
  tags = {
    Environment        = local.environment
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
    AutoShutdown       = "True"
    ProjectId          = local.project_id
  }

  # Maintain env_tags for backward compatibility
  env_tags = {
    Environment        = local.environment
    AutoShutdown       = "True"
    DataClassification = "Internal"
    ProjectId          = local.project_id
  }
}
