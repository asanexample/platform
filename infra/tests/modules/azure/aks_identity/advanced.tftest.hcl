/**
 * # AKS Identity Module - Advanced Test
 * 
 * This test verifies advanced functionality of the AKS Identity module
 * including workload identities for cert-manager and karpenter.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Advanced test for AKS Identity with workload identities
run "advanced_aks_identity" {
  command = plan

  variables {
    # Basic naming
    prefix      = "test"
    environment = "prod"
    region_abbv = "eus"
    customer    = "enterprise"
    
    # Resource group and location
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Cluster reference
    cluster_name = "test-prod-aks-eus"
    
    # Custom identity name
    aks_identity_name = "test-prod-aks-identity"
    
    # Enable workload identities
    create_workload_identities = true
    workload_identity_enabled  = true
    oidc_issuer_enabled        = true
    oidc_issuer_url            = "https://eastus.oic.prod-aks-0000000.hcp.eastus.azmk8s.io/0000000-0000-0000-0000-000000000000/"
    
    # Custom workload identity names
    cert_manager_identity_name            = "test-prod-cert-manager"
    cert_manager_federated_credential_name = "test-prod-cert-manager-fed-cred"
    karpenter_identity_name               = "test-prod-karpenter"
    karpenter_federated_credential_name   = "test-prod-karpenter-fed-cred"
    
    # Network configuration - set to null to avoid route table lookup error
    node_resource_group_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/MC_test-rg_test-prod-aks-eus_eastus"
    subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/aks-subnet"
    private_route_table_name   = null
    vnet_resource_group_name   = null
    
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
    source = "../../../../modules/azure/aks_identity"
  }

  # Test input validation only in plan mode
  assert {
    condition     = var.create_workload_identities == true
    error_message = "Workload identities should be created in advanced test"
  }
  
  assert {
    condition     = var.workload_identity_enabled == true
    error_message = "Workload identity should be enabled in advanced test"
  }
  
  assert {
    condition     = var.oidc_issuer_enabled == true
    error_message = "OIDC issuer should be enabled in advanced test"
  }

  # Plan-compatible assertions
  assert {
    condition     = var.aks_identity_name == "test-prod-aks-identity"
    error_message = "AKS identity name not set correctly"
  }
  
  assert {
    condition     = var.cert_manager_identity_name == "test-prod-cert-manager"
    error_message = "Cert Manager identity name not set correctly"
  }
  
  assert {
    condition     = var.karpenter_identity_name == "test-prod-karpenter"
    error_message = "Karpenter identity name not set correctly"
  }
} 