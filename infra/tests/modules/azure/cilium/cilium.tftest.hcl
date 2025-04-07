/**
 * # Cilium Module Tests
 */

# Mock the AKS cluster data source
mock_provider "azurerm" {
  mock_data "azurerm_kubernetes_cluster" {
    defaults = {
      name                = "test-aks-cluster"
      resource_group_name = "test-resource-group"
      kube_config = [{
        host                   = "https://test-aks-api-server.hcp.eastus.azmk8s.io:443"
        client_certificate     = "REDACTED"
        client_key             = "REDACTED"
        cluster_ca_certificate = "REDACTED"
      }]
    }
  }
}

# Basic Cilium installation test
run "basic_cilium_installation" {
  variables {
    cluster_name        = "test-aks-cluster"
    resource_group_name = "test-resource-group"
    helm_chart_version  = "1.17.2"
    aksbyocni_enabled   = true
    gateway_api_enabled = true
    hubble_enabled      = true
  }

  # Test that the basic configuration is valid
  assert {
    condition     = module.helm_release_name == "cilium"
    error_message = "Helm release name should be 'cilium'"
  }

  assert {
    condition     = module.helm_release_version == "1.17.2"
    error_message = "Helm chart version should be '1.17.2'"
  }

  assert {
    condition     = module.namespace == "kube-system"
    error_message = "Namespace should be 'kube-system'"
  }

  # Test that AKS BYOCNI integration is enabled
  assert {
    condition     = module.cilium_values.aksbyocni.enabled == true
    error_message = "AKS BYOCNI integration should be enabled"
  }
}

# Advanced Cilium configuration test
run "advanced_cilium_configuration" {
  variables {
    cluster_name                   = "test-aks-cluster"
    resource_group_name            = "test-resource-group"
    helm_chart_version             = "1.17.2"
    aksbyocni_enabled              = true
    gateway_api_enabled            = true
    hubble_enabled                 = true
    hubble_relay_enabled           = true
    hubble_ui_enabled              = true
    prometheus_enabled             = true
    prometheus_service_monitor_enabled = true
    operator_prometheus_enabled    = true
    kube_proxy_replacement         = "false"
    resources_limits_cpu           = "1000m"
    resources_limits_memory        = "1Gi"
    operator_resources_limits_cpu  = "500m"
    operator_resources_limits_memory = "512Mi"
  }

  # Test that advanced configuration settings are correctly applied
  assert {
    condition     = module.cilium_values.prometheus.enabled == true
    error_message = "Prometheus metrics should be enabled"
  }

  assert {
    condition     = module.cilium_values.prometheus.serviceMonitor.enabled == true
    error_message = "Prometheus ServiceMonitor should be enabled"
  }

  assert {
    condition     = module.cilium_values.hubble.relay.enabled == true
    error_message = "Hubble Relay should be enabled"
  }

  assert {
    condition     = module.cilium_values.hubble.ui.enabled == true
    error_message = "Hubble UI should be enabled"
  }

  assert {
    condition     = module.cilium_values.resources.limits.cpu == "1000m"
    error_message = "Cilium agent CPU limits should be set to 1000m"
  }

  assert {
    condition     = module.cilium_values.operator.resources.limits.memory == "512Mi"
    error_message = "Cilium operator memory limits should be set to 512Mi"
  }
} 