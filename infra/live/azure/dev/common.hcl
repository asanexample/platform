# Common variables for all dev environment regions

locals {
  # Environment variables
  env      = "dev"
  prefix   = "vip"
  customer = null
  
  # Common tags
  tags = {
    Environment        = "dev"
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
  }
} 