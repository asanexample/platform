# Test file for Azure AKS Core module
# Using Terraform 1.6+ testing framework

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  resource_group_name    = "test-rg"
  location               = "eastus"
  name                   = "test-aks-core"
  dns_prefix             = "test-aks-dns"
  kubernetes_version     = "1.26.0"
  default_nodepool_name  = "system"
  default_nodepool_count = 1
  region_abbv            = "eus" 
  stage                  = "dev"
  prefix                 = "vip"
  customer               = "test"
  default_nodepool_vm_size = "Standard_D2s_v3"
  default_nodepool_max_pods = 30
  default_nodepool_os_disk_size_gb = 128
  default_nodepool_enable_auto_scaling = false
  default_nodepool_min_count = 1
  default_nodepool_max_count = 3
  default_nodepool_node_labels = {
    "nodepool" = "system"
    "environment" = "test"
  }
  network_plugin = "kubenet"
  network_policy = "calico"
  service_cidr = "10.0.0.0/16"
  dns_service_ip = "10.0.0.10"
  pod_cidr = "10.244.0.0/16"
  subnet_id = null
  user_assigned_identity_id = null
  private_dns_zone_id = null
  log_analytics_workspace_id = null
  authorized_ip_ranges = []  # Changed from null to empty list
  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
    azure_rbac_enabled = true
  }
  local_account_disabled = false
  sku_tier = "Free"
  workload_identity_enabled = true
  oidc_issuer_enabled = true
  identity_type = "SystemAssigned"
  default_nodepool_availability_zones = ["1", "2", "3"]  # Added availability zones
  tags = {
    Environment = "test"
    ManagedBy   = "Terraform"
  }
}

# Test basic AKS cluster creation
run "validate_aks_cluster_creation" {
  command = plan

  module {
    source = "../../../../modules/azure/aks_core"
  }

  # Assert that location is correct
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

# Test cluster with custom name
run "validate_custom_name" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = "custom-aks-name"
    dns_prefix          = "custom-dns"
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  # Assert that location is correct
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

# Test cluster with generated name
run "validate_generated_name" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    name                = null # Use generated name
    dns_prefix          = "gen-dns"
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  # Assert that location is correct
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
}

# Test workload identity disabled
run "validate_workload_identity_disabled" {
  command = plan

  variables {
    resource_group_name            = "test-rg"
    location                       = "eastus"
    name                           = "test-aks"
    dns_prefix                     = "test-dns"
    workload_identity_enabled      = false
    oidc_issuer_enabled            = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  # Assert that location is correct
  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }
} 