/**
 * # Azure Storage Account Module
 *
 * This module creates an Azure Storage Account with optional containers,
 * network rules, and private endpoints. It's designed to be flexible enough for 
 * various use cases including application data, logging, and more.
 */

locals {
  # Generate storage account name if not provided
  # Azure storage account names must be between 3-24 characters and use only lowercase letters and numbers
  storage_account_name = var.name != "" ? var.name : "${var.name_components.prefix}${var.name_components.environment}${var.name_components.region_abbv}sa${var.name_components.instance}"

  # Set private endpoint name if not specified
  # Default format follows naming convention: <storage-account-name>-pe
  private_endpoint_name = var.private_endpoint.name != "" ? var.private_endpoint.name : "${local.storage_account_name}-pe"

  # Add standard tags to all resources
  # These ensure consistent tagging across all storage resources
  default_tags = {
    Environment        = var.name_components.environment
    ManagedBy          = "Terraform"
    Component          = "Storage"
    DataClassification = "Internal"
  }
  tags = merge(local.default_tags, var.tags)

  # Determine if we need a managed identity for customer-managed key encryption
  customer_managed_key_enabled = var.customer_managed_key != null
  needs_identity               = local.customer_managed_key_enabled
}

# Main storage account resource
# Configures the core storage account with all specified properties
resource "azurerm_storage_account" "this" {
  # Basic properties
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Storage account type configuration
  account_kind             = var.account_kind             # StorageV2 is recommended for most use cases
  account_tier             = var.account_tier             # Standard or Premium tier
  account_replication_type = var.account_replication_type # How data is replicated (LRS, ZRS, GRS, etc.)
  access_tier              = var.access_tier              # Hot or Cool tier for cost optimization

  # Security settings
  min_tls_version                 = var.min_tls_version                 # Enforce minimum TLS version
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public # Control public access permissions
  shared_access_key_enabled       = var.shared_access_key_enabled       # Enable/disable SAS key authentication

  # Network access settings
  public_network_access_enabled = var.public_network_access_enabled

  # Identity configuration for customer-managed keys
  dynamic "identity" {
    for_each = local.needs_identity ? [1] : []
    content {
      type         = var.customer_managed_key != null && var.customer_managed_key.use_system_assigned_identity ? "SystemAssigned" : "UserAssigned"
      identity_ids = var.customer_managed_key != null && !var.customer_managed_key.use_system_assigned_identity ? [var.customer_managed_key.user_assigned_identity_id] : []
    }
  }

  # Customer-managed key configuration
  dynamic "customer_managed_key" {
    for_each = local.customer_managed_key_enabled ? [var.customer_managed_key] : []
    content {
      key_vault_key_id          = customer_managed_key.value.key_vault_key_id
      user_assigned_identity_id = customer_managed_key.value.use_system_assigned_identity ? null : customer_managed_key.value.user_assigned_identity_id
    }
  }

  # Blob-specific configuration options
  blob_properties {
    # Data management features
    versioning_enabled       = var.blob_versioning_enabled  # Track blob versions
    last_access_time_enabled = var.last_access_time_enabled # Track last access time for lifecycle management
    change_feed_enabled      = var.change_feed_enabled      # Track changes for auditing/replication

    # Container retention policy - only created if days are specified
    # This controls how long deleted containers are recoverable
    dynamic "container_delete_retention_policy" {
      for_each = var.container_delete_retention_days != null ? [1] : []
      content {
        days = var.container_delete_retention_days
      }
    }

    # Blob retention policy - only created if days are specified
    # This controls how long deleted blobs are recoverable
    dynamic "delete_retention_policy" {
      for_each = var.blob_delete_retention_days != null ? [1] : []
      content {
        days = var.blob_delete_retention_days
      }
    }

    # CORS configuration - only created if CORS rules are specified
    # Enables cross-origin requests to the storage account from web browsers
    dynamic "cors_rule" {
      for_each = var.cors_rules
      content {
        allowed_origins    = cors_rule.value.allowed_origins
        allowed_methods    = cors_rule.value.allowed_methods
        allowed_headers    = cors_rule.value.allowed_headers
        exposed_headers    = cors_rule.value.exposed_headers
        max_age_in_seconds = cors_rule.value.max_age_in_seconds
      }
    }
  }

  # Network rules block - only created when needed
  # This manages network-level access controls for the storage account
  dynamic "network_rules" {
    for_each = length(var.network_rules) > 0 || var.private_endpoint.create ? [1] : []
    content {
      default_action             = var.network_rules.default_action             # Allow or Deny as default
      bypass                     = var.network_rules.bypass                     # Services that can bypass restrictions
      ip_rules                   = var.network_rules.ip_rules                   # Allowed IP addresses/ranges
      virtual_network_subnet_ids = var.network_rules.virtual_network_subnet_ids # Allowed VNet subnets
    }
  }

  # Apply all tags
  tags = local.tags
}

# Note: Key auto-rotation for customer-managed keys is not implemented
# because the 'azurerm_key_vault_key_managed_storage_account_auto_rotation' resource
# is not available in provider version 4.23.0.
# When upgrading to a newer provider version, auto-rotation can be implemented
# using the appropriate resource.

# Lifecycle management policy for blobs
# This resource automates tiering and deletion of blobs based on configured rules
resource "azurerm_storage_management_policy" "lifecycle" {
  # Only create lifecycle policy when rules are specified
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  # Connect policy to the storage account
  storage_account_id = azurerm_storage_account.this.id

  # Create a rule for each lifecycle rule in the input variables
  dynamic "rule" {
    for_each = { for rule in var.lifecycle_rules : rule.name => rule }

    content {
      name    = rule.value.name    # Rule name (must be unique)
      enabled = rule.value.enabled # Whether rule is active

      # Filters determine which blobs the rule applies to
      filters {
        prefix_match = rule.value.prefix_match # Apply to blobs with these prefixes
        blob_types   = ["blockBlob"]           # Only support block blobs currently
      }

      # Actions to take on matching blobs
      actions {
        # Base blob actions (on the current version)
        base_blob {
          # Delete blobs after specified days
          delete_after_days_since_modification_greater_than = rule.value.delete_action != null ? rule.value.delete_action.days_after_modification_greater_than : null

          # Tier blobs to cool storage after specified days (for cost optimization)
          tier_to_cool_after_days_since_modification_greater_than = rule.value.tier_to_cool_action != null ? rule.value.tier_to_cool_action.days_after_modification_greater_than : null

          # Tier blobs to archive storage after specified days (for long-term retention)
          tier_to_archive_after_days_since_modification_greater_than = rule.value.tier_to_archive_action != null ? rule.value.tier_to_archive_action.days_after_modification_greater_than : null
        }
      }
    }
  }
}

# Storage containers within the account
# Optional creation based on the create_containers flag
resource "azurerm_storage_container" "containers" {
  for_each              = var.create_containers ? var.containers : {} # Skip if create_containers is false
  name                  = each.value.name                             # Container name
  storage_account_id    = azurerm_storage_account.this.id             # Parent storage account
  container_access_type = each.value.container_access_type            # Access level (private, blob, container)
}

# Private endpoint for the storage account
# Only created when specified in the private_endpoint variable
resource "azurerm_private_endpoint" "storage" {
  count               = var.private_endpoint.create ? 1 : 0 # Only create if requested
  name                = local.private_endpoint_name         # Endpoint name
  location            = var.location                        # Must be in same region as storage
  resource_group_name = var.resource_group_name             # Resource group
  subnet_id           = var.private_endpoint.subnet_id      # Subnet to place the private endpoint in

  # Connection to the storage account
  private_service_connection {
    name                           = "${local.private_endpoint_name}-connection" # Connection name
    private_connection_resource_id = azurerm_storage_account.this.id             # Target resource
    is_manual_connection           = false                                       # Auto-approved connection
    subresource_names              = var.private_endpoint.subresource_names      # Target subresources (blob, queue, etc)
  }

  # DNS zone integration (if specified)
  # This enables automatic DNS resolution for the private endpoint
  dynamic "private_dns_zone_group" {
    for_each = length(var.private_endpoint.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "${local.storage_account_name}-dns"
      private_dns_zone_ids = var.private_endpoint.private_dns_zone_ids
    }
  }

  # Apply all tags
  tags = local.tags
}

# Role assignments for Entra ID authentication
# This creates RBAC role assignments for principals to access the storage account
resource "azurerm_role_assignment" "this" {
  count                = length(var.role_assignments)
  principal_id         = var.role_assignments[count.index].principal_id
  role_definition_name = var.role_assignments[count.index].role_definition_name
  role_definition_id   = var.role_assignments[count.index].role_definition_id
  scope                = var.role_assignments[count.index].scope != null ? var.role_assignments[count.index].scope : azurerm_storage_account.this.id
  description          = var.role_assignments[count.index].description

  # Skip deletion of role assignments by default when the resource is deleted
  # This ensures that roles aren't unintentionally removed if the terraform resource is deleted
  lifecycle {
    prevent_destroy = true
  }
} 