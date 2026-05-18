# Common configuration for Azure Container Registry deployments across environments

# Set the Terraform module source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/container_registry"
}

# Local variables for configuration
locals {
  # Not using any special source URL - using local repo
}

# Common inputs for all environments
inputs = {
  # Creation control - create ACR by default
  create_registry = true

  # Common ACR configuration
  admin_enabled = false # Disable admin for security - use AKS integration instead
  lock_resource = true  # Lock resource to prevent accidental deletion

  # Image retention policy (can be overridden per environment)
  retention_policy_days = 30

  # AKS integration - enabled by default, can be overridden per environment
  aks_integration_enabled = true  # Enable integration with AKS
  enable_aks_acr_push     = false # Only enable pull access by default

  # Tags applied to all environments (merged with environment-specific tags)
  tags = {
    "module"     = "container-registry"
    "managed-by" = "terraform"
  }
} 