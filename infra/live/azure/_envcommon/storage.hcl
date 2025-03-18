# ---------------------------------------------------------------------------------------------------------------------
# COMMON STORAGE CONFIGURATION
# This file defines standard storage settings for different environments
# ---------------------------------------------------------------------------------------------------------------------

# This file is meant to be included in terragrunt.hcl files directly

inputs = {
  # Standard containers to create in all environments
  storage_containers = {
    "assets" = {
      name                  = "assets"
      container_access_type = "private"
    },
    "public" = {
      name                  = "public"
      container_access_type = get_env("TF_VAR_environment", "dev") == "prod" ? "private" : "blob"
    },
    "pdf" = {
      name                  = "pdf"
      container_access_type = "private"
    }
  }
  
  # Storage account settings based on environment
  storage_account_tier     = "Standard"
  storage_replication_type = get_env("TF_VAR_environment", "dev") == "prod" ? "ZRS" : "LRS"
  storage_allow_public     = get_env("TF_VAR_environment", "dev") == "prod" ? false : true
  
  # CORS settings for storage
  storage_cors_rules = get_env("TF_VAR_environment", "dev") == "prod" ? [] : [
    {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "OPTIONS"]
      allowed_origins    = ["*"]
      exposed_headers    = ["Content-Length", "Content-Type"]
      max_age_in_seconds = 3600
    }
  ]
} 