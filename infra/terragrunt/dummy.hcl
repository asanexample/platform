# Dummy file with default values for when env.hcl cannot be found
# This prevents errors when reading configuration

locals {
  # Default environment variables
  environment     = "dev"
  subscription_id = get_env("ARM_SUBSCRIPTION_ID", "")
} 