# Common Terragrunt configuration for Azure Key Vault

terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${get_repo_root()}/infra/modules/azure//key_vault"
}

locals {
  # Extract the variables we need for easy access
  base_source_url = find_in_parent_folders("infra")
}

inputs = {
  # Default Key Vault configuration
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  soft_delete_retention_days      = 90
  purge_protection_enabled        = true
  sku_name                        = "standard"

  # Default network ACLs
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }

  # Default private endpoint configuration (will be overridden in specific env)
  enable_private_endpoint = true
  create_private_dns_zone = true
  private_dns_zone_name   = "privatelink.vaultcore.azure.net"
} 