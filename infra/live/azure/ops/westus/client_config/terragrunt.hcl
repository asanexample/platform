# Terragrunt configuration for Azure client config in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Define Terraform source
terraform {
  source = "${get_repo_root()}/infra/modules/azure//client_config"
}

# Specify inputs
inputs = {}
