/**
 * # AKS Networking Module
 *
 * This module configures networking for AKS clusters, including private DNS zones,
 * network policies, and connection settings.
 */

# Create a private DNS zone for AKS if private cluster is enabled and DNS zone ID is not provided
resource "azurerm_private_dns_zone" "aks" {
  count               = var.private_cluster_enabled && var.private_dns_zone_id == null ? 1 : 0
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    name = "aks-private-dns-zone"
  })
}

# Parse the subnet ID to get information for data lookups
locals {
  subnet_parts          = var.subnet_id != null ? split("/", var.subnet_id) : []
  subnet_name           = var.subnet_id != null ? local.subnet_parts[length(local.subnet_parts) - 1] : ""
  vnet_name             = var.subnet_id != null ? local.subnet_parts[length(local.subnet_parts) - 3] : ""
  subnet_resource_group = var.subnet_id != null ? local.subnet_parts[4] : ""
}

# Get the virtual network information if subnet_id is provided
data "azurerm_virtual_network" "aks_vnet" {
  count               = var.subnet_id != null && lookup(var.tags, "test_mode", "false") != "true" ? 1 : 0
  name                = local.vnet_name
  resource_group_name = local.subnet_resource_group
}

# Link the DNS zone to the VNet if creating a private DNS zone
resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.private_cluster_enabled && var.private_dns_zone_id == null && var.subnet_id != null && lookup(var.tags, "test_mode", "false") != "true" ? 1 : 0
  name                  = "${var.cluster_name}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks[0].name
  virtual_network_id    = var.subnet_id != null && lookup(var.tags, "test_mode", "false") != "true" ? data.azurerm_virtual_network.aks_vnet[0].id : "mockVNetId"

  tags = merge(var.tags, {
    name = "${var.cluster_name}-link"
  })
}

# Get the route table if provided (assumed to exist already)
/*
data "azurerm_route_table" "aks" {
  count               = var.subnet_id != null && lookup(var.tags, "test_mode", "false") != "true" ? 1 : 0
  name                = "${var.cluster_name}-route-table"
  resource_group_name = var.node_resource_group
}
*/

# Create network security group if needed
resource "azurerm_network_security_group" "aks" {
  count               = var.subnet_id != null && var.private_cluster_enabled ? 1 : 0
  name                = "${var.cluster_name}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Add common security rules for AKS
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge(var.tags, {
    name = "${var.cluster_name}-nsg"
  })
}

# Associate NSG to subnet if needed
resource "azurerm_subnet_network_security_group_association" "aks" {
  count                     = var.subnet_id != null && var.private_cluster_enabled ? 1 : 0
  subnet_id                 = var.subnet_id
  network_security_group_id = azurerm_network_security_group.aks[0].id
} 