/**
 * # Azure Key Vault Module
 *
 * This module creates an Azure Key Vault with configurable access policies,
 * network rules, and private endpoints. It's designed to be flexible for use
 * in various security scenarios including secret management, certificate management,
 * and encryption key management.
 */

# Data source to get the current client configuration
data "azurerm_client_config" "current" {}

locals {
  # Generate key vault name if not provided using naming components
  key_vault_name = var.name != null ? var.name : "${var.name_components.workload}${var.name_components.environment}${var.name_components.region_abbv}kv${var.name_components.instance}"

  # Set private endpoint name if not specified
  # Default format follows naming convention: <key-vault-name>-pe
  private_endpoint_name = var.private_endpoint.name != "" ? var.private_endpoint.name : "${local.key_vault_name}-pe"

  # Add standard tags to all resources
  default_tags = {
    Environment        = var.name_components.environment
    ManagedBy          = "Terraform"
    Component          = "KeyVault"
    DataClassification = "Confidential"
  }
  tags = merge(local.default_tags, var.tags)
}

# Create the Key Vault
resource "azurerm_key_vault" "key_vault" {
  count               = var.create ? 1 : 0
  name                = local.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name

  enable_rbac_authorization   = var.enable_rbac_authorization
  enabled_for_disk_encryption = var.enabled_for_disk_encryption
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled    = var.purge_protection_enabled
  soft_delete_retention_days  = var.soft_delete_retention_days
  sku_name                    = var.sku_name

  # Network access configuration - control public access
  public_network_access_enabled = var.private_endpoint.create ? false : var.public_network_access_enabled

  # Configure network ACLs if specified
  dynamic "network_acls" {
    for_each = var.network_acls != null ? [var.network_acls] : []
    content {
      bypass                     = network_acls.value.bypass
      default_action             = network_acls.value.default_action
      ip_rules                   = network_acls.value.ip_rules
      virtual_network_subnet_ids = network_acls.value.virtual_network_subnet_ids
    }
  }

  tags = local.tags
}

# Add access policies if RBAC is not enabled
resource "azurerm_key_vault_access_policy" "policies" {
  for_each = var.create ? (var.enable_rbac_authorization ? {} : var.access_policies) : {}

  key_vault_id = azurerm_key_vault.key_vault[0].id
  tenant_id    = each.value.tenant_id != null ? each.value.tenant_id : data.azurerm_client_config.current.tenant_id
  object_id    = each.value.object_id

  key_permissions         = each.value.key_permissions
  secret_permissions      = each.value.secret_permissions
  certificate_permissions = each.value.certificate_permissions
  storage_permissions     = each.value.storage_permissions
}

# Private endpoint for the key vault
resource "azurerm_private_endpoint" "key_vault" {
  count               = var.create && var.private_endpoint.create ? 1 : 0
  name                = local.private_endpoint_name
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint.subnet_id

  # Connection to the key vault
  private_service_connection {
    name                           = "${local.private_endpoint_name}-connection"
    private_connection_resource_id = azurerm_key_vault.key_vault[0].id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  # DNS zone integration (if specified)
  dynamic "private_dns_zone_group" {
    for_each = length(var.private_endpoint.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "${local.key_vault_name}-dns"
      private_dns_zone_ids = var.private_endpoint.private_dns_zone_ids
    }
  }

  tags = local.tags
}
