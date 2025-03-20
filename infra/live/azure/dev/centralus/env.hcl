# Environment configuration for Azure dev environment

locals {
  environment = "dev"
  
  # Common tags for this environment
  env_tags = {
    Environment        = local.environment
    AutoShutdown       = "True"
    DataClassification = "Internal"
  }
} 