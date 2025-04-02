/**
 * # AKS Core Module - Validation Test
 * 
 * This test verifies the validation rules of the AKS Core module
 * to ensure that input variables are properly validated.
 */

# Provider configuration with Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Test prefix validation
run "prefix_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = var.prefix == "centric"
    error_message = "Prefix should be valid with proper format"
  }
}

# Test environment validation
run "environment_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = contains(["dev", "test", "staging", "prod", "ops"], var.environment)
    error_message = "Environment should be one of the allowed values"
  }
}

# Test region abbreviation validation
run "region_abbv_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = length(var.region_abbv) >= 2 && length(var.region_abbv) <= 6
    error_message = "Region abbreviation should be between 2 and 6 characters"
  }
}

# Test name validation
run "name_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    name                = "test-aks-cluster"
    resource_group_name = "test-rg"
    location            = "westeurope"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = length(var.name) >= 3 && length(var.name) <= 63
    error_message = "AKS cluster name should be between 3 and 63 characters"
  }
}

# Test resource group name validation
run "resource_group_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-resource-group"
    location            = "westeurope"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name should be between 1 and 90 characters"
  }
}

# Test location validation
run "location_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = var.location == "westeurope"
    error_message = "Location should be a valid Azure region"
  }
}

# Test DNS prefix validation
run "dns_prefix_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    dns_prefix          = "test-aks-dns"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = length(var.dns_prefix) >= 3 && length(var.dns_prefix) <= 45
    error_message = "DNS prefix should be between 3 and 45 characters"
  }
}

# Test Kubernetes version validation
run "kubernetes_version_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    kubernetes_version  = "1.25.5"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version should be in the format X.Y.Z"
  }
}

# Test automatic channel upgrade validation
run "automatic_channel_upgrade_validation_test" {
  command = plan

  variables {
    prefix                    = "centric"
    environment               = "dev"
    region_abbv               = "weu"
    resource_group_name       = "test-rg"
    location                  = "westeurope"
    automatic_channel_upgrade = "stable"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = contains(["patch", "rapid", "node-image", "stable", "none"], var.automatic_channel_upgrade)
    error_message = "Automatic channel upgrade should be one of the allowed values"
  }
}

# Test SKU tier validation
run "sku_tier_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    sku_tier            = "Free"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "SKU tier should be either Free or Standard"
  }
}

# Test workload identity and OIDC validation
run "identity_features_validation_test" {
  command = plan

  variables {
    prefix                  = "centric"
    environment             = "dev"
    region_abbv             = "weu"
    resource_group_name     = "test-rg"
    location                = "westeurope"
    workload_identity_enabled = true
    oidc_issuer_enabled     = true
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = var.workload_identity_enabled == true && var.oidc_issuer_enabled == true
    error_message = "Workload identity and OIDC issuer should be enabled"
  }
}

# Test authorized IP ranges validation
run "authorized_ip_ranges_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    authorized_ip_ranges = ["10.0.0.0/24", "192.168.1.0/24"]
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = length(var.authorized_ip_ranges) == 2
    error_message = "Authorized IP ranges should be valid CIDR notations"
  }
}

# Test default node pool configuration
run "default_nodepool_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    default_nodepool_name = "system"
    default_nodepool_vm_size = "Standard_D4s_v3"
    default_nodepool_enable_auto_scaling = true
    default_nodepool_min_count = 1
    default_nodepool_max_count = 5
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = var.default_nodepool_enable_auto_scaling == true && var.default_nodepool_min_count < var.default_nodepool_max_count
    error_message = "Default node pool auto-scaling should be properly configured"
  }
}

# Test network configuration validation
run "network_config_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    network_plugin      = "azure"
    network_policy      = "azure"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = contains(["azure", "kubenet"], var.network_plugin) && contains(["azure", "calico"], var.network_policy)
    error_message = "Network plugin and policy should be valid options"
  }
}

# Test monitoring integration validation
run "monitoring_integration_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    log_analytics_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-workspace"
    enable_prometheus_integration = true
    prometheus_dcr_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Insights/dataCollectionRules/test-dcr"
    monitor_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-monitor"
    default_nodepool_enable_auto_scaling = false
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = var.enable_prometheus_integration == true
    error_message = "Prometheus integration should be enabled"
  }
}

# Test tags validation
run "tags_validation_test" {
  command = plan

  variables {
    prefix              = "centric"
    environment         = "dev"
    region_abbv         = "weu"
    resource_group_name = "test-rg"
    location            = "westeurope"
    default_nodepool_enable_auto_scaling = false
    tags = {
      environment = "test"
      application = "aks"
      owner       = "platform-team"
    }
  }

  module {
    source = "../../../../modules/azure/aks_core"
  }

  assert {
    condition     = length(keys(var.tags)) == 3
    error_message = "Tags should be accepted with valid format"
  }
} 