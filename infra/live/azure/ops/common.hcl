# Common variables for dev environment across all regions
# This file contains all environment configuration that was previously split between common.hcl and env.hcl.
# For backward compatibility, a symbolic link from env.hcl to this file is created.

locals {
  # Environment variables
  env               = "ops"
  environment       = "ops"  # For backward compatibility
  prefix            = "vip"
  customer          = null
  subscription_name = "innovation-test"
  subscription_id   = "9dc5edc4-8c4e-41a1-a4f8-2183c4e91954"  # Innovation-Operations subscription ID
  tenant_id         = "c945e155-be68-4477-b8d7-01939adbfe55"  # Azure tenant ID
  
  # Common tags
  tags = {
    Environment        = local.environment
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
    AutoShutdown       = "True"
    SubscriptionName   = local.subscription_name
  }
  
  # Maintain env_tags for backward compatibility
  env_tags = {
    Environment        = local.environment
    AutoShutdown       = "True"
    DataClassification = "Internal"
    SubscriptionName   = local.subscription_name
  }
} 