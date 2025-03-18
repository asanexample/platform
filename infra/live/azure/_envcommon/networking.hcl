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
# For the complete CIDR allocation strategy documentation, see: infra/docs/network-topology.md
#
# MULTI-CLOUD CIDR ALLOCATION
# - AWS Infrastructure: 10.100.0.0/16
# - Azure Infrastructure: 10.101.0.0/16
#
# AZURE REGION ALLOCATIONS
# - eastus:      10.101.0.0/20
# - eastus2:     10.101.16.0/20
# - westus:      10.101.32.0/20
# - westus2:     10.101.48.0/20
# - northeurope: 10.101.64.0/20
# - westeurope:  10.101.80.0/20
#
# AVAILABILITY ZONE DESIGN
# Each region follows a 3-AZ design with specialized subnet types:
# - Each Availability Zone gets a /24 CIDR block
# - Four subnet types within each AZ:
#   - Kubernetes Subnets (/24): For Kubernetes worker nodes
#   - Services Subnets (/26): For application services
#   - Endpoints Subnets (/27): For private endpoints and service connections
#   - Transit Subnets (/28): For transit gateways and network connections
# ---------------------------------------------------------------------------------------------------------------------

# Define common input variables for all network deployments
inputs = {
  # Network Security Group Rules
  # These are the default NSG rules that will be applied to all subnets
  default_nsg_rules = {
    # Allow all traffic between resources within the same virtual network
    # Critical for internal communication between services and components
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
    
    # Block all other inbound traffic that isn't explicitly allowed
    # This is a security best practice (deny-by-default)
    # Low priority (4096) ensures it runs after all other rules
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
    
    # Allow all internal traffic between resources within the same virtual network
    # Enables services to communicate with each other within the VNet
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
    
    # Allow resources to access internet destinations
    # Enables services to reach external APIs, package repositories, etc.
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
    
    # Block all other outbound traffic that isn't explicitly allowed
    # Security boundary to prevent unauthorized egress
    # Low priority (4096) ensures it runs after all other rules
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