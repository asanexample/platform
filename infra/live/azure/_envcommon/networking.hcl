# Common Terragrunt configuration for Azure networking.
# Shared defaults for all environments — environment-specific address_space and subnets
# come from each region's network.hcl (the authoritative CIDR source).
# See allocations.csv for the full multi-cloud CIDR allocation plan.

terraform {
  source = "${get_repo_root()}/infra/modules/azure//networking"
}

inputs = {
  dns_servers = null
  subnets     = {}

  enable_aks_networking       = false
  aks_subnet_name             = null
  aks_cluster_name            = null
  aks_private_cluster_enabled = true
  aks_node_resource_group     = null
} 