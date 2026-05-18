# Common Terragrunt configuration for Azure Storage

terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${get_repo_root()}/infra/modules/azure//storage_account"
}

locals {
  # Extract the variables we need for easy access
  base_source_url = find_in_parent_folders("infra")
}

inputs = {
  # Default Storage Account configuration
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Default container configuration
  enable_blob_storage = true
  containers = {
    "assets" = {
      name                  = "assets",
      container_access_type = "private"
    },
    "public" = {
      name                  = "public",
      container_access_type = "blob"
    },
    "pdf" = {
      name                  = "pdf",
      container_access_type = "private"
    }
  }

  # Default network configuration
  network_rules = {
    default_action             = "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }

  # Enable public network access by default
  public_network_access_enabled = true

  # Default private endpoint configuration (will be overridden in specific env)
  private_endpoint = {
    create            = true
    subresource_names = ["blob"]
  }

  # Disable shared access keys in favor of Entra ID authentication
  shared_access_key_enabled = false

  # Role assignments will need to be added in specific environment modules
  # Example:
  # role_assignments = [
  #   {
  #     principal_id         = "00000000-0000-0000-0000-000000000000" # Object ID of user, group, or service principal
  #     role_definition_name = "Storage Blob Data Contributor"
  #     description          = "Grant Blob Data Contributor role to DevOps team"
  #   }
  # ]
} 