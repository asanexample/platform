/**
 * # Azure Container Registry Module
 *
 * This module provisions and configures an Azure Container Registry (ACR) instance,
 * which can be used to store and manage container images and artifacts.
 * The module supports different SKUs, network configurations, encryption settings,
 * and integration with Azure Kubernetes Service.
 */

# Get the current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate a name for the ACR if not provided
# ACR names must be globally unique, lowercase, and alphanumeric only
locals {
  # Generate default name if not provided
  acr_name = var.name != null ? var.name : lower("${var.prefix}${var.environment}acr${var.region_abbv}")
  
  # Default network rule set if none provided
  default_network_rule_set = {
    default_action = "Deny"
    ip_rules       = []
    virtual_network = []
  }
  
  # Determine whether to use geo-replication (only supported in Premium SKU)
  geo_replication_enabled = var.sku == "Premium" && length(var.geo_replication_locations) > 0
}

# Create the Azure Container Registry
resource "azurerm_container_registry" "acr" {
  count                    = var.create_registry ? 1 : 0
  name                     = local.acr_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = var.sku
  admin_enabled            = var.admin_enabled
  
  # Identity management
  identity {
    type = "SystemAssigned"
  }
  
  # Premium tier features
  dynamic "georeplications" {
    for_each = local.geo_replication_enabled ? var.geo_replication_locations : []
    
    content {
      location                = georeplications.value.location
      zone_redundancy_enabled = lookup(georeplications.value, "zone_redundancy_enabled", false)
      tags                    = lookup(georeplications.value, "tags", {})
    }
  }
  
  # Network rule set - only available in Standard and Premium tiers
  # Limited to IP rules for now as subnet integration requires more complex setup
  dynamic "network_rule_set" {
    for_each = var.sku != "Basic" && var.network_rule_set != null ? [var.network_rule_set] : []
    
    content {
      default_action = network_rule_set.value.default_action
      
      dynamic "ip_rule" {
        for_each = network_rule_set.value.ip_rules
        
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }
    }
  }
  
  # Encryption settings - only available in Premium tier
  dynamic "encryption" {
    for_each = var.sku == "Premium" && var.encryption_enabled ? [1] : []
    
    content {
      key_vault_key_id   = var.key_vault_key_id
      identity_client_id = var.encryption_identity_id
    }
  }
  
  # Public access configuration
  public_network_access_enabled = var.public_network_access_enabled
  
  # Zone redundancy - only available in Premium tier
  zone_redundancy_enabled = var.sku == "Premium" ? var.zone_redundancy_enabled : false
  
  # Data endpoint settings
  data_endpoint_enabled = var.sku == "Premium" ? var.data_endpoint_enabled : false
  
  # Configure all resources with the provided tags
  tags = var.tags
}

# Create role assignment for AKS to pull images from ACR (if AKS integration is enabled)
resource "azurerm_role_assignment" "acr_pull" {
  count                = var.create_registry && var.aks_integration_enabled && var.aks_principal_id != null ? 1 : 0
  scope                = var.create_registry ? azurerm_container_registry.acr[0].id : ""
  role_definition_name = "AcrPull"
  principal_id         = var.aks_principal_id
  
  # Add description
  description = "Allows AKS to pull images from ACR"
}

# Optionally add a role assignment for pushing images to ACR
resource "azurerm_role_assignment" "acr_push" {
  count                = var.create_registry && var.aks_integration_enabled && var.enable_aks_acr_push && var.aks_principal_id != null ? 1 : 0
  scope                = var.create_registry ? azurerm_container_registry.acr[0].id : ""
  role_definition_name = "AcrPush"
  principal_id         = var.aks_principal_id
  
  # Add description
  description = "Allows AKS to push images to ACR"
}

# Lock the container registry if specified
resource "azurerm_management_lock" "acr_lock" {
  count      = var.create_registry && var.lock_resource ? 1 : 0
  name       = "${local.acr_name}-lock"
  scope      = var.create_registry ? azurerm_container_registry.acr[0].id : ""
  lock_level = "CanNotDelete"
  notes      = "Locked to prevent accidental deletion of the container registry"
} 