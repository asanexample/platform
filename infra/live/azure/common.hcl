# Common variables shared across all regions and environments
# This file contains global configuration for the platform

locals {
  # Project variables
  prefix   = "vip"
  customer = null
  
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
} 