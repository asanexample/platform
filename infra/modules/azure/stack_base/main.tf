# Base infrastructure stack — composes resource_group, networking, and key_vault
# into a single deployable unit. Demonstrates the composite module pattern:
# small single-purpose modules wired together with explicit dependencies.

module "resource_group" {
  source = "../resource_group"

  create      = var.create
  name        = var.name
  location    = var.location
  environment = var.environment
  workload    = var.workload
  region_abbv = var.region_abbv
  tags        = var.tags
}

module "networking" {
  source = "../networking"

  create              = var.create
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  vnet_name           = "${var.name}-vnet"
  address_space       = var.address_space
  subnets             = var.subnets
  dns_servers         = []

  enable_aks_networking = var.enable_aks_networking
  aks_subnet_name      = var.aks_subnet_name
  aks_cluster_name     = var.aks_cluster_name

  tags = var.tags
}

module "key_vault" {
  source = "../key_vault"

  create              = var.create && var.enable_key_vault
  name                = null
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  sku_name            = var.key_vault_sku

  tags = var.tags
}
