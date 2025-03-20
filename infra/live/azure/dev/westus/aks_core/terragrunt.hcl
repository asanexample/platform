# Terragrunt configuration for Azure AKS Core in westus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Load network configuration
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  
  # Extract commonly used variables
  env         = local.common_vars.locals.env
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = "westus"
  region_abbv = "wus"
  tags        = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for AKS Core
include "aks_core_common" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/azure/aks_core.hcl"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
    location = "westus"
  }
}

dependency "networking" {
  config_path = "../networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    vnet_name = "mock-vnet"
    subnet_ids = {
      "az1-kubernetes" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-kubernetes"
    }
    aks_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/privateDnsZones/privatelink.westus.azmk8s.io"
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  # Resource details
  name        = dependency.naming.outputs.aks_cluster
  resource_group_name = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location
  dns_prefix = "${local.prefix}-${local.env}-wus"
  
  # Environment-specific overrides
  kubernetes_version = "1.32"
  sku_tier = "Standard"
  local_account_disabled = true
  workload_identity_enabled = true
  oidc_issuer_enabled = true
  
  # Azure AD integration for this environment
  azure_ad_integration = {
    enable = true
    admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
    azure_rbac_enabled = true
    tenant_id = null
  }
  
  # Identity configuration
  user_assigned_identity_id = dependency.aks_identity.outputs.aks_identity_id
  
  # Network configuration specific to this environment
  network_profile = {
    network_plugin = "none"
    network_policy = null
    outbound_type = "loadBalancer"
    service_cidr = "10.0.0.0/16"
    dns_service_ip = "10.0.0.10"
    pod_cidr = "10.244.0.0/16"
    load_balancer_sku = "standard"
  }
  
  # Subnet and private cluster configuration
  subnet_id = dependency.networking.outputs.subnet_ids["az1-kubernetes"]
  private_dns_zone_id = dependency.networking.outputs.aks_private_dns_zone_id
  
  # Default node pool overrides
  default_node_pool = {
    name = "system"
    vm_size = "Standard_D2s_v4"
    enable_auto_scaling = true
    node_count = 2
    min_count = 2
    max_count = 3
    availability_zones = ["1", "2", "3"]
    max_pods = 110
    os_disk_size_gb = 128
    node_labels = {
      "role" = "system"
      "node-priority" = "regular"
    }
    node_taints = []
    os_disk_type = "Managed"
    os_sku = "Ubuntu"
    ultra_ssd_enabled = false
  }
  
  # Tags
  tags = merge(local.tags, {
    "network-cilium-managed-by" = "cilium"
    "cilium-version" = "1.17.2"
  })
} 