# Terragrunt configuration for Azure AKS Core in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root configuration (root.hcl)
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include the common configuration for AKS Core
include "aks_core_common" {
  path = find_in_parent_folders("azure/_envcommon/aks_core.hcl")
}

# Set dependencies for this module (these will merge with the common inputs)
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
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

dependency "networking" {
  config_path = "../networking"

  # Mock outputs for plan and validation
  mock_outputs = {
    vnet_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    vnet_name = "mock-vnet"
    subnet_ids = {
      "az1-kubernetes" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-kubernetes"
    }
    aks_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/privateDnsZones/privatelink.${include.base.locals.region}.azmk8s.io"
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"

  # Mock outputs for plan and validation
  mock_outputs = {
    aks_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
}

# Add dependency on Log Analytics workspace for monitoring
dependency "log_analytics" {
  config_path = "../log_analytics"

  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-log-analytics"
    name = "mock-log-analytics"
  }
}

dependency "prometheus_dcr" {
  config_path = "../prometheus_dcr"
  mock_outputs = {
    dcr_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Insights/dataCollectionRules/mock-dcr-prometheus"
  }
}

dependency "monitor_workspace" {
  config_path = "../monitor_workspace"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Monitor/accounts/mock-monitor-workspace"
  }
}

inputs = {
  create = true

  # Environment variables
  environment = include.base.locals.env
  workload = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  # Resource details
  name                = dependency.naming.outputs.aks_cluster
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  dns_prefix          = "${include.base.locals.workload}-${include.base.locals.env}-${include.base.locals.region_abbv}"

  # Environment-specific overrides
  kubernetes_version        = "1.32.0"  # Specific version - Azure will automatically upgrade within this minor version
  sku_tier                  = "Standard"
  local_account_disabled    = true  # Require Azure AD integration
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # Azure AD integration for this environment
  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]  # Replace with actual Azure AD group IDs in production
    azure_rbac_enabled     = true
  }

  # Identity configuration
  user_assigned_identity_id = dependency.aks_identity.outputs.aks_identity_id

  # Network configuration specific to this environment - IMPORTANT: Setting network_plugin to "none" for Cilium
  network_plugin    = "none"  # No CNI installed - Cilium will be installed via Helm
  network_policy    = null    # Not used with Cilium
  outbound_type     = "loadBalancer"
  service_cidr      = "10.0.0.0/16"
  dns_service_ip    = "10.0.0.10"
  pod_cidr          = "10.244.0.0/16"
  load_balancer_sku = "standard"

  # Subnet and private cluster configuration
  subnet_id           = dependency.networking.outputs.subnet_ids["az1-kubernetes"]
  private_dns_zone_id = dependency.networking.outputs.aks_private_dns_zone_id

  # Default node pool overrides
  default_node_pool = {
    name                = "system"
    vm_size             = "Standard_D4ds_v5"
    enable_auto_scaling = true
    node_count          = 3
    min_count           = 3
    max_count           = 5
    max_pods            = 110  # With Cilium (network_plugin = "none"), pods get IPs from pod_cidr, not from the subnet
    os_disk_size_gb     = 128
    node_labels = {
      "role"          = "system"
      "node-priority" = "high"
      "kubernetes.azure.com/scalesetpriority" = "regular"
    }
    only_critical_addons_enabled = true  # This will apply CriticalAddonsOnly=true:NoSchedule taint
    os_disk_type      = "Managed"
    os_sku            = "Ubuntu"
    ultra_ssd_enabled = false
  }

  microsoft_defender_enabled     = true
  enable_prometheus_integration = true
  monitor_workspace_id          = dependency.monitor_workspace.outputs.id
  prometheus_dcr_id             = dependency.prometheus_dcr.outputs.dcr_id

  diagnostic_settings = [{
    name                       = "${dependency.naming.outputs.aks_cluster}-diag"
    log_analytics_workspace_id = dependency.log_analytics.outputs.id
    enabled_log_categories = [
      "kube-apiserver",
      "kube-audit",
      "kube-audit-admin",
      "kube-controller-manager",
      "kube-scheduler",
      "cluster-autoscaler",
      "guard"
    ]
    metric_categories  = ["AllMetrics"]
    log_retention_days = 30
  }]

  # RBAC role assignments for accessing AKS monitoring
  role_assignments = [
    {
      principal_id         = "403dc11a-5399-4f10-9515-91f048eea58a"  # Current user
      role_definition_name = "Monitoring Reader"
      description          = "Grants access to view AKS monitoring data"
    }
  ]

  # Connect to Log Analytics Workspace
  log_analytics_workspace_id = dependency.log_analytics.outputs.id

  # Tags
  tags = merge(include.base.locals.tags, {
    "network-cilium-managed-by" = "cilium"
    "cilium-version"            = "1.17.2"
    "monitoring-level"          = "comprehensive"
    "monitoring-enabled"        = "true"
  })
}
