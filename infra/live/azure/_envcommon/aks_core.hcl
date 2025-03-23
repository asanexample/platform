# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR AKS CORE
# This is the common component configuration for Azure Kubernetes Service. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Terraform module source for AKS
terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${get_repo_root()}/infra/modules/azure//aks_core"
}

# ---------------------------------------------------------------------------------------------------------------------
# COMMON CONFIGURATION FOR AKS CORE
# These are the common configurations that should be the same across all environments
# ---------------------------------------------------------------------------------------------------------------------

# Default inputs for all environments
inputs = {
  # Kubernetes version
  kubernetes_version = "1.32.0"  # By specifying minor version, Azure will automatically upgrade patch versions
  
  # Require Azure AD integration and disable local accounts
  local_account_disabled = true
  
  # Azure AD Integration (required for all environments)
  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = []  # To be provided in environment-specific config
    azure_rbac_enabled     = true
  }
  
  # Default node pool configuration (can be overridden in environment-specific configs)
  default_node_pool = {
    name                = "system"
    vm_size             = "Standard_D4s_v3"
    enable_auto_scaling = true
    node_count          = 3
    min_count           = 2
    max_count           = 5
    availability_zones  = ["1", "2", "3"]
    node_labels = {
      "nodepool-type" = "system"
      "environment"   = "system"
      "nodepoolos"    = "linux"
    }
    node_taints         = []
    os_disk_size_gb     = 100
    os_disk_type        = "Managed"
    os_sku              = "Ubuntu"
    ultra_ssd_enabled   = false
    max_pods            = 110
  }
  
  # Network Settings - No CNI installed by default (Cilium will be installed via Helm)
  network_plugin    = "none"  # Required for Cilium
  network_policy    = null    # Not used with Cilium
  outbound_type     = "loadBalancer"
  service_cidr      = null  # Must be provided in environment-specific configs
  dns_service_ip    = null  # Must be provided in environment-specific configs
  pod_cidr          = null  # Must be provided in environment-specific configs
  load_balancer_sku = "standard"
  
  # Common cluster settings
  private_cluster_enabled = true
  sku_tier                = "Free"  # Use "Standard" for production
  
  # Identity type should be consistent across environments
  identity_type = "UserAssigned"
  
  # Common feature flags
  network_contributor_role_enabled = true
  azure_policy_enabled             = true
  
  # Enable workload identity and OIDC issuer for pod-based authentication
  workload_identity_enabled = true
  oidc_issuer_enabled       = true
  
  key_vault_secrets_provider = {
    enabled = true
    secret_rotation_enabled = true
    rotation_poll_interval  = "2m"
  }
  
  # Common maintenance window (customize per environment if needed)
  maintenance_window = {
    allowed = [
      {
        day   = "Sunday"
        hours = [0, 1, 2]
      }
    ]
    not_allowed = []
  }
} 