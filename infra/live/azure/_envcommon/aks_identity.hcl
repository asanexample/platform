# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR AKS IDENTITY
# This is the common component configuration for AKS Identity. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Common Terragrunt configuration for Azure AKS Identity

terraform {
  # Instead of just referencing the identities module, reference the parent directory
  # This ensures all sibling modules (like naming) are available for relative imports
  source = "${get_repo_root()}/infra/modules/azure//identities"

  # Remove absolute paths, they're not portable
  # extra_arguments "common_vars" {
  #   commands = ["init", "plan", "apply", "destroy"]
  # }
}

# ---------------------------------------------------------------------------------------------------------------------
# SHARED VARIABLES
# These variables are used across all environments and regions
# ---------------------------------------------------------------------------------------------------------------------
locals {
  # Extract the variables we need for easy access
  base_source_url = find_in_parent_folders("infra")

  # Extract environment from env.hcl
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment

  # Extract region information from region.hcl
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region      = local.region_vars.locals.region

  # Get common tags from the environment
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  common_tags = local.common_vars.locals.tags
}

# Default inputs that typically won't need to be overridden in specific environments
inputs = {
  # Default identity configuration
  identity_type = "UserAssigned"
  tags          = {}

  # The name and resource group will typically come from other modules in environment-specific configs

  # Default tags that should be applied to all AKS identity resources
  tags = merge(local.common_tags, {
    "ResourceType" = "ManagedIdentity"
    "Component"    = "AKS"
  })

  # Default role assignments
  role_assignments = {
    "Network Contributor" = {
      scope                            = null # Must be provided in environment-specific config
      skip_service_principal_aad_check = true
    }
  }
} 