/**
 * # Azure Networking Module
 *
 * This module creates an Azure virtual network with subnets and network security groups.
 * It also supports AKS-specific networking features when enabled.
 */

# Create the virtual network
resource "azurerm_virtual_network" "vnet" {
  count               = var.create ? 1 : 0
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = length(var.dns_servers) > 0 ? var.dns_servers : null
  tags                = var.tags
}

# Create a subnet for each entry in the subnets map
resource "azurerm_subnet" "subnet" {
  for_each = var.create ? var.subnets : {}

  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = each.value.address_prefixes

  service_endpoints = each.value.service_endpoints

  dynamic "delegation" {
    for_each = each.value.delegation
    content {
      name = delegation.key
      dynamic "service_delegation" {
        for_each = delegation.value
        content {
          name    = service_delegation.value.name
          actions = lookup(service_delegation.value, "actions", null) != null ? toset([lookup(service_delegation.value, "actions", null)]) : null
        }
      }
    }
  }
}

# Create a network security group for each subnet
resource "azurerm_network_security_group" "nsg" {
  for_each = var.create ? var.subnets : {}

  name                = "${each.key}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Associate Network Security Groups with subnets, excluding AzureFirewallSubnet
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  for_each = var.create ? {
    for k, v in var.subnets : k => v
    if k != "AzureFirewallSubnet" # Exclude AzureFirewallSubnet as it doesn't support NSG associations
  } : {}

  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id
}

# ----------- AKS Networking Features -----------

# Determine if we should add AKS-specific NSG rules
locals {
  configure_aks_nsg = var.create && var.enable_aks_networking && var.aks_subnet_name != null ? contains(keys(var.subnets), var.aks_subnet_name) : false
}

# Add AKS-specific NSG rules when enabled
resource "azurerm_network_security_rule" "aks_allow_lb" {
  count                       = local.configure_aks_nsg ? 1 : 0
  name                        = "AllowAzureLoadBalancer"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg[var.aks_subnet_name].name
}

resource "azurerm_network_security_rule" "aks_deny_inbound" {
  count                       = local.configure_aks_nsg ? 1 : 0
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg[var.aks_subnet_name].name
}

# Allow Cilium agent health checks
resource "azurerm_network_security_rule" "aks_allow_cilium_health" {
  count                       = local.configure_aks_nsg ? 1 : 0
  name                        = "AllowCiliumHealth"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "4240"
  source_address_prefixes     = var.address_space # Allow from all VNet address space
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg[var.aks_subnet_name].name
}

# Allow VXLAN tunnel traffic for Cilium overlay
resource "azurerm_network_security_rule" "aks_allow_vxlan" {
  count                       = local.configure_aks_nsg ? 1 : 0
  name                        = "AllowVXLAN"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "8472"
  source_address_prefixes     = var.address_space # Allow from all VNet address space
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg[var.aks_subnet_name].name
}

# Allow node-to-node traffic for all protocols within all kubernetes subnets
resource "azurerm_network_security_rule" "aks_allow_node_communication" {
  count                  = local.configure_aks_nsg ? 1 : 0
  name                   = "AllowNodeCommunication"
  priority               = 130
  direction              = "Inbound"
  access                 = "Allow"
  protocol               = "*"
  source_port_range      = "*"
  destination_port_range = "*"
  source_address_prefixes = [
    for subnet_name, subnet in var.subnets :
    subnet.address_prefixes[0] if can(regex("kubernetes$", subnet_name))
  ]
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg[var.aks_subnet_name].name
}

# Create a private DNS zone for AKS if private cluster is enabled and DNS zone ID is not provided
resource "azurerm_private_dns_zone" "aks" {
  count               = var.create && var.enable_aks_networking && var.aks_private_cluster_enabled && var.aks_private_dns_zone_id == null ? 1 : 0
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, {
    name = "aks-private-dns-zone"
  })
}

# Link the DNS zone to the VNet if creating a private DNS zone
resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.create && var.enable_aks_networking && var.aks_private_cluster_enabled && var.aks_private_dns_zone_id == null ? 1 : 0
  name                  = "${var.aks_cluster_name}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aks[0].name
  virtual_network_id    = azurerm_virtual_network.vnet[0].id

  tags = merge(var.tags, {
    name = "${var.aks_cluster_name}-link"
  })
} 