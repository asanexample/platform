/**
 * # AKS Core Module - Basic Test
 * 
 * This test verifies the basic functionality of the AKS core module
 * with minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Variables for Azure credentials passed via environment variables
variables {
  subscription_id = ""
  tenant_id = ""
}

# Basic test for AKS cluster creation with minimal configuration
run "basic_aks_cluster" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Use auto-generated name
    name        = null
    prefix      = "test"
    environment = "dev"
    region_abbv = "eus"
    
    # Basic cluster configuration
    kubernetes_version     = "1.28.5"
    local_account_disabled = true
    sku_tier               = "Free"
    
    # Workload identity settings
    workload_identity_enabled = true
    oidc_issuer_enabled       = true
    
    # Default node pool configuration
    default_nodepool_name            = "system"
    default_nodepool_count           = 1
    default_nodepool_vm_size         = "Standard_D4s_v4"
    default_nodepool_max_pods        = 30
    default_nodepool_os_disk_size_gb = 128
    default_nodepool_node_labels     = {
      "nodepool-type" = "system"
      "environment"   = "dev"
    }
    default_nodepool_enable_auto_scaling = false
    
    # Network configuration
    network_plugin     = "azure"
    network_policy     = "azure"
    dns_service_ip     = "10.0.0.10"
    service_cidr       = "10.0.0.0/16"
    pod_cidr           = "10.244.0.0/16"
    docker_bridge_cidr = "172.17.0.1/16"
    
    # Identity type
    identity_type = "SystemAssigned"
    
    # No Azure AD integration for basic test
    azure_active_directory_role_based_access_control = null
    
    # No monitor workspace association for basic test
    log_analytics_workspace_id = null
    
    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  # Validate AKS cluster properties
  assert {
    condition     = output.name == "test-dev-aks-eus"
    error_message = "AKS cluster name doesn't match expected value"
  }

  assert {
    condition     = output.kubernetes_version == "1.28.5"
    error_message = "Kubernetes version doesn't match expected value"
  }

  assert {
    condition     = output.location == "eastus"
    error_message = "Location doesn't match expected value"
  }
} 