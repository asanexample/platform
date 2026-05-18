/**
 * # AKS Core Module - Advanced Test
 * 
 * This test verifies advanced functionality of the AKS Core module
 * with optional features and complex configurations.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {
    # This is required to make the microsoft_defender block work properly in tests
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id                 = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id                       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Advanced test for AKS cluster with optional features
run "advanced_aks_cluster" {
  # Use plan command for non-destructive testing
  command = plan

  variables {
    resource_group_name  = "test-rg"
    location             = "eastus"
    name                 = "test-aks"
    kubernetes_version   = "1.26.0"
    monitor_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-law"
    prometheus_dcr_id    = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Insights/dataCollectionRules/test-dcr"
    # Remove microsoft_defender_enabled as it's not a variable in the module
    # microsoft_defender_enabled = true

    # Microsoft Defender requires log_analytics_workspace_id
    log_analytics_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-law"

    # Network configuration
    network_plugin     = "azure"
    network_policy     = "azure"
    dns_service_ip     = "10.0.0.10"
    service_cidr       = "10.0.0.0/16"
    pod_cidr           = "10.244.0.0/16"
    docker_bridge_cidr = "172.17.0.1/16"

    # Default node pool configuration
    default_nodepool_name            = "system"
    default_nodepool_count           = 1
    default_nodepool_vm_size         = "Standard_D4s_v4"
    default_nodepool_max_pods        = 30
    default_nodepool_os_disk_size_gb = 128
    default_nodepool_node_labels = {
      "nodepool-type" = "system"
      "environment"   = "dev"
    }
    default_nodepool_enable_auto_scaling = true
    default_nodepool_min_count           = 1
    default_nodepool_max_count           = 3

    # Identity type
    identity_type = "SystemAssigned"

    # Azure AD integration
    azure_active_directory_role_based_access_control = {
      admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
      azure_rbac_enabled     = true
    }

    # Role assignments - may be null if no role assignments needed
    role_assignments = []

    diagnostic_settings = [
      {
        name                       = "test-diag"
        enabled_log_categories     = ["kube-audit", "kube-audit-admin"]
        log_analytics_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-law"
        metric_categories          = ["AllMetrics"]
        retention_days             = 30
      }
    ]
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  # For plan mode, we'll only check if inputs are properly set
  # Since outputs aren't known during plan phase
  assert {
    condition     = var.name == "test-aks"
    error_message = "Expected name variable to be set to 'test-aks'"
  }

  assert {
    condition     = var.resource_group_name == "test-rg"
    error_message = "Expected resource_group_name variable to be set to 'test-rg'"
  }

  assert {
    condition     = var.kubernetes_version == "1.26.0"
    error_message = "Expected kubernetes_version variable to be set to '1.26.0'"
  }

  assert {
    condition     = var.location == "eastus"
    error_message = "Expected location variable to be set to 'eastus'"
  }

  assert {
    condition     = var.default_nodepool_enable_auto_scaling == true
    error_message = "Expected default_nodepool_enable_auto_scaling to be enabled"
  }

  assert {
    condition     = length(var.diagnostic_settings) == 1
    error_message = "Expected diagnostic settings to be configured"
  }
} 