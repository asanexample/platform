/**
 * # Shared Infrastructure Variables
 * 
 * Variables for deploying networking, storage, and key vault in a single resource group.
 */

# Naming variables
variable "prefix" {
  description = "Prefix to use for resource naming (usually 'vip')"
  type        = string
  default     = "vip"
}

variable "customer" {
  description = "Customer name to use in resource naming (optional for shared resources)"
  type        = string
  default     = null
}

variable "stage" {
  description = "Environment stage (dev, test, prod, etc.)"
  type        = string
}

variable "region_abbv" {
  description = "Abbreviated Azure region name (e.g., eus, wus, etc.)"
  type        = string
}

# Resource group variables - Deprecated, maintained for backward compatibility
variable "resource_group_name" {
  description = "DEPRECATED: Name of the resource group is now derived from the naming module"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Network variables - Deprecated, maintained for backward compatibility
variable "vnet_name" {
  description = "DEPRECATED: Name of the virtual network is now derived from the naming module"
  type        = string
  default     = null
}

variable "address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnet configurations"
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
    delegation        = optional(map(list(map(string))), {})
  }))
}

variable "dns_servers" {
  description = "List of DNS servers to use with the virtual network"
  type        = list(string)
  default     = []
}

# Storage variables - Deprecated, maintained for backward compatibility
variable "storage_name_components" {
  description = "DEPRECATED: Storage account name is now derived from the naming module"
  type = object({
    prefix      = optional(string, "app")
    environment = optional(string, "dev")
    region_abbv = optional(string, "eus")
    instance    = optional(string, "001")
  })
  default = {}
}

variable "storage_account_name" {
  description = "DEPRECATED: Storage account name is now derived from the naming module"
  type        = string
  default     = null
}

variable "storage_account_tier" {
  description = "Tier of storage account to create"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
}

variable "storage_network_default_action" {
  description = "Default action for storage network rules"
  type        = string
  default     = "Deny"
}

variable "storage_network_bypass" {
  description = "List of services to bypass storage network rules"
  type        = list(string)
  default     = ["AzureServices"]
}

variable "storage_allowed_subnets" {
  description = "List of subnet names from the network module that can access storage"
  type        = list(string)
  default     = []
}

variable "storage_containers" {
  description = "Map of containers to create in the storage account"
  type = map(object({
    name                  = string
    container_access_type = optional(string, "private")
  }))
  default = {}
}

variable "storage_allow_public" {
  description = "Whether to allow public access to storage containers"
  type        = bool
  default     = false
}

variable "storage_cors_rules" {
  description = "CORS rules for the storage account blob service"
  type = list(object({
    allowed_origins    = list(string)
    allowed_methods    = list(string)
    allowed_headers    = list(string)
    exposed_headers    = list(string)
    max_age_in_seconds = number
  }))
  default = []
}

# Key Vault variables
variable "create_key_vault" {
  description = "Whether to create a key vault as part of the hosting infrastructure"
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "The SKU name of the key vault (standard or premium)"
  type        = string
  default     = "standard"
}

variable "key_vault_enable_rbac" {
  description = "Whether to enable RBAC authorization for the key vault"
  type        = bool
  default     = true
}

variable "key_vault_enable_disk_encryption" {
  description = "Whether to enable the key vault for disk encryption"
  type        = bool
  default     = false
}

variable "key_vault_purge_protection" {
  description = "Whether to enable purge protection on the key vault"
  type        = bool
  default     = true
}

variable "key_vault_retention_days" {
  description = "Soft delete retention days for the key vault (7-90 days)"
  type        = number
  default     = 90
}

variable "key_vault_public_access" {
  description = "Whether to enable public network access to the key vault"
  type        = bool
  default     = false
}

variable "key_vault_allowed_subnets" {
  description = "List of subnet names that are allowed to access the key vault"
  type        = list(string)
  default     = null
}

variable "key_vault_access_policies" {
  description = "Map of access policies for the key vault (used only when RBAC is disabled)"
  type = map(object({
    tenant_id               = optional(string)
    object_id               = string
    key_permissions         = optional(list(string), [])
    secret_permissions      = optional(list(string), [])
    certificate_permissions = optional(list(string), [])
    storage_permissions     = optional(list(string), [])
  }))
  default = {}
}

variable "key_vault_private_endpoint_subnet" {
  description = "Subnet name for the key vault private endpoint (empty means no private endpoint)"
  type        = string
  default     = ""
}

variable "key_vault_private_dns_zone_ids" {
  description = "List of private DNS zone IDs for the key vault private endpoint"
  type        = list(string)
  default     = []
}

# AKS Cluster variables
variable "create_aks_cluster" {
  description = "Whether to create an AKS cluster as part of the hosting infrastructure"
  type        = bool
  default     = false
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version to use for the AKS cluster"
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "SKU tier for the AKS cluster (Free or Standard)"
  type        = string
  default     = "Free"
}

variable "aks_dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = null
}

# AKS Network Configuration
variable "aks_network_plugin" {
  description = "Network plugin to use for the AKS cluster (azure, kubenet, or none)"
  type        = string
  default     = "azure"
}

variable "aks_network_plugin_mode" {
  description = "Network plugin mode to use for the AKS cluster (overlay or transparent)"
  type        = string
  default     = "overlay"
}

variable "aks_network_policy" {
  description = "Network policy to use for the AKS cluster (azure, calico)"
  type        = string
  default     = "azure"
}

variable "aks_network_data_plane" {
  description = "Network data plane to use for the AKS cluster (azure, cilium)"
  type        = string
  default     = "azure"
}

variable "aks_pod_cidr" {
  description = "CIDR range for pods"
  type        = string
  default     = "10.244.0.0/16"
}

variable "aks_service_cidr" {
  description = "CIDR range for services"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "IP address within the service CIDR for DNS service"
  type        = string
  default     = "10.0.0.10"
}

variable "aks_docker_bridge_cidr" {
  description = "CIDR range for the Docker bridge network"
  type        = string
  default     = "172.17.0.1/16"
}

variable "aks_subnet_name" {
  description = "Name of the subnet where the AKS cluster will be deployed"
  type        = string
  default     = ""
}

variable "aks_availability_zones" {
  description = "A list of availability zones to deploy the AKS cluster across"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "aks_az_subnet_names" {
  description = "Map of availability zone to subnet name where AKS nodes should be deployed"
  type        = map(string)
  default     = null
}

variable "aks_use_network_topology" {
  description = "Whether to use the network topology defined in allocations.csv"
  type        = bool
  default     = false
}

variable "aks_private_cluster_enabled" {
  description = "Enable private cluster for the AKS cluster"
  type        = bool
  default     = false
}

variable "aks_private_dns_zone_id" {
  description = "ID of the private DNS zone for the AKS cluster"
  type        = string
  default     = null
}

variable "aks_private_cluster_public_fqdn_enabled" {
  description = "Enable public FQDN for a private cluster"
  type        = bool
  default     = false
}

variable "aks_authorized_ip_ranges" {
  description = "List of authorized IP ranges for the AKS cluster API"
  type        = list(string)
  default     = []
}

# AKS Default Node Pool
variable "aks_default_nodepool_name" {
  description = "Name of the default node pool"
  type        = string
  default     = "system"
}

variable "aks_default_nodepool_vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v4"
}

variable "aks_default_nodepool_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 1
}

# AKS Identity Configuration
variable "aks_workload_identity_enabled" {
  description = "Enable workload identity for the AKS cluster"
  type        = bool
  default     = true
}

variable "aks_oidc_issuer_enabled" {
  description = "Enable OIDC issuer for the AKS cluster"
  type        = bool
  default     = true
}

variable "aks_local_account_disabled" {
  description = "Disable local accounts for the AKS cluster"
  type        = bool
  default     = true
}

variable "aks_log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for AKS monitoring"
  type        = string
  default     = null
}

# AKS Application Node Pool
variable "aks_app_node_pool_enabled" {
  description = "Enable application node pool"
  type        = bool
  default     = true
}

variable "aks_app_node_pool_name" {
  description = "Name of the application node pool"
  type        = string
  default     = "app"
}

variable "aks_app_node_pool_vm_size" {
  description = "VM size for the application node pool"
  type        = string
  default     = "Standard_D4s_v4"
}

variable "aks_app_node_pool_node_count" {
  description = "Initial number of nodes in the application node pool"
  type        = number
  default     = 2
}

variable "deployment_mode" {
  description = "The deployment mode to control phased deployments. Options: 'full', 'infrastructure', 'identity'"
  type        = string
  default     = "full"
} 