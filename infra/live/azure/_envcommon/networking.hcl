# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR AZURE NETWORKING
# This is the common component configuration for Azure networking. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration, which has settings common across all components
include "root" {
  path = find_in_parent_folders()
}

# Include the component configuration, which has settings that are common across environments
include "env" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/tags.hcl"
  expose = true
}

# Include naming conventions
include "naming" {
  path   = "${dirname(find_in_parent_folders())}/_envcommon/naming.hcl"
  expose = true
}

# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL NETWORK ARCHITECTURE & CIDR ALLOCATION
# 
# We follow a hierarchical CIDR allocation strategy for multi-cloud environments that provides clear organizational
# boundaries. This is combined with a Kubernetes-optimized subnet design that divides each region's address space
# into availability zones with specialized subnet types.
#
# For the complete CIDR allocation strategy documentation, see: infra/docs/cidr-allocation.md
#
# AZURE NETWORK ADDRESS SPACE
# 10.16.0.0/12 - Azure Infrastructure
#   10.17.0.0/16 - Azure Dev Environment
#     10.17.0.0/23 - Azure Dev East US
#     10.17.2.0/23 - Azure Dev West US
#   10.18.0.0/16 - Azure Test Environment (Reserved)
#   10.19.0.0/16 - Azure Production Environment (Reserved)
#
# REGIONAL NETWORK DESIGN
# Each region follows a 3-AZ Kubernetes-optimized design:
# - Each Availability Zone gets a /25 CIDR block
# - Specialized subnet types within each AZ:
#   - Node Subnets (/26): For Kubernetes worker nodes
#   - Load Balancer Subnets (/28): For load balancers
#   - Endpoint Subnets (/28): For private endpoints and service connections
#   - Transit Subnets (/29): For transit gateways or routing
# ---------------------------------------------------------------------------------------------------------------------

# Define common input variables for all network deployments
inputs = {
  # Network Security Group Rules
  # These are the default NSG rules that will be applied to all subnets
  default_nsg_rules = {
    allow_vnet_inbound = {
      name                       = "allow_vnet_inbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    deny_all_inbound = {
      name                       = "deny_all_inbound"
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
    allow_vnet_outbound = {
      name                       = "allow_vnet_outbound"
      priority                   = 100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    allow_internet_outbound = {
      name                       = "allow_internet_outbound"
      priority                   = 110
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
    }
    deny_all_outbound = {
      name                       = "deny_all_outbound"
      priority                   = 4096
      direction                  = "Outbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
} 