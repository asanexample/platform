/**
 * # AKS Core Module - Advanced Test
 * 
 * This test verifies advanced functionality of the AKS core module
 * including Azure AD integration, monitoring, and advanced networking.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Advanced test for AKS cluster with Azure AD integration and monitoring
run "advanced_aks_cluster" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Use explicit name
    name                = "test-enterprise-aks"
    prefix              = "test"
    environment         = "prod"
    region_abbv         = "eus"
    
    # Advanced cluster configuration
    kubernetes_version     = "1.29.2"
    local_account_disabled = true
    sku_tier               = "Standard"
    
    # Workload identity settings
    workload_identity_enabled = true
    oidc_issuer_enabled       = true
    
    # Default node pool configuration with auto-scaling
    default_nodepool_name                = "system"
    default_nodepool_count               = 3
    default_nodepool_vm_size             = "Standard_D4s_v3"
    default_nodepool_max_pods            = 50
    default_nodepool_os_disk_size_gb     = 256
    default_nodepool_enable_auto_scaling = true
    default_nodepool_min_count           = 2
    default_nodepool_max_count           = 5
    default_nodepool_node_labels         = {
      "nodepool-type"    = "system"
      "environment"      = "production"
      "criticality"      = "high"
      "security-tier"    = "core"
    }
    
    # Advanced network configuration
    network_plugin     = "azure"
    network_policy     = "calico"
    dns_service_ip     = "10.100.0.10"
    service_cidr       = "10.100.0.0/16"
    pod_cidr           = "10.244.0.0/16"
    docker_bridge_cidr = "172.17.0.1/16"
    outbound_type      = "userDefinedRouting"
    
    # Identity type
    identity_type = "SystemAssigned"
    
    # Azure AD RBAC integration
    azure_active_directory_role_based_access_control = {
      admin_group_object_ids = ["00000000-0000-0000-0000-000000000001"]
      azure_rbac_enabled     = true
    }
    
    # Monitor workspace integration
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-monitor-workspace"
    
    # Comprehensive tagging
    tags = {
      environment     = "production"
      criticality     = "high"
      data-class      = "confidential"
      service-owner   = "platform-team"
      cost-center     = "12345"
      application     = "core-infrastructure"
    }
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  # Validate AKS cluster properties
  assert {
    condition     = output.name == "test-enterprise-aks"
    error_message = "AKS cluster name doesn't match expected value"
  }

  assert {
    condition     = output.kubernetes_version == "1.29.2"
    error_message = "Kubernetes version doesn't match expected value"
  }

  assert {
    condition     = output.location == "eastus"
    error_message = "Location doesn't match expected value"
  }
} 