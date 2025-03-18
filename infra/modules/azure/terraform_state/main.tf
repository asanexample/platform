/**
 * # Azure Terraform State Storage Module
 *
 * This module creates an Azure Storage Account specifically configured for Terraform state storage,
 * following all best practices for security and durability. It provisions a specialized storage
 * account with optimized settings for Terraform state management:
 * - Enforces blob versioning for state history
 * - Uses ZRS replication at minimum for durability
 * - Configures appropriate retention policies
 * - Creates a dedicated 'tfstate' container
 * - Sets secure access controls
 */

locals {
  # Default container name for Terraform state files
  # Uses a custom name if provided, otherwise defaults to "tfstate"
  tfstate_container_name = var.tfstate_container_name != "" ? var.tfstate_container_name : "tfstate"
}

# Use the base storage module with specialized configuration for Terraform state
module "storage_account" {
  source = "../storage"

  # Pass through basic parameters to the underlying storage module
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = var.storage_account_name
  name_components     = var.name_components
  tags                = var.tags

  # ========== Terraform State-Specific Settings ==========
  
  # Storage account configuration - enforcing best practices for state storage
  account_kind              = "StorageV2"  # Modern storage account type with all features
  account_tier              = "Standard"   # Standard performance tier is sufficient for state
  
  # Ensure at least ZRS replication for state durability
  # Zone-Redundant Storage provides higher durability than LRS
  # If user specifies something better than LRS (like GRS), use that instead
  account_replication_type  = var.account_replication_type != "LRS" ? var.account_replication_type : "ZRS"
  
  # Always enable versioning for state history and recovery
  blob_versioning_enabled   = true
  
  # Retention policies for state recovery
  # These settings ensure deleted state can be recovered for a reasonable period
  blob_delete_retention_days      = coalesce(var.blob_delete_retention_days, 7)
  container_delete_retention_days = coalesce(var.container_delete_retention_days, 7)

  # Create required containers
  # Always create the tfstate container, and merge any additional user-specified containers
  containers = merge(var.additional_containers, {
    "tfstate" = {
      name                  = local.tfstate_container_name
      container_access_type = "private"  # Always private for security
    }
  })
  
  # Security settings for Terraform state
  # These settings enforce proper security practices for state storage
  allow_nested_items_to_be_public = false  # Never allow public access for state
  blob_public_access_enabled      = false  # Disable public access at account level
  shared_access_key_enabled       = true   # Required for Terraform backend to access state
  min_tls_version                 = "TLS1_2"  # Enforce modern TLS
  
  # Optional advanced features
  # These are useful for auditing and lifecycle management
  change_feed_enabled     = var.change_feed_enabled      # Track changes to blobs
  last_access_time_enabled = var.last_access_time_enabled # Track when blobs were last accessed
  
  # Network and security settings - passed through from user configuration
  network_rules    = var.network_rules
  private_endpoint = var.private_endpoint
  
  # Lifecycle management rules (optional)
  lifecycle_rules = var.lifecycle_rules
} 