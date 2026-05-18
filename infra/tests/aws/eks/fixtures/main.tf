variable "create" {
  type    = bool
  default = true
}

variable "vpc_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "address_space" {
  type = list(string)
}

variable "subnets" {
  type = any
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "enable_secrets_encryption" {
  type    = bool
  default = true
}

variable "create_node_group" {
  type    = bool
  default = false
}

variable "bootstrap_self_managed_addons" {
  type    = bool
  default = true
}

variable "access_entries" {
  type    = any
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  kubernetes_subnet_ids = var.create ? [
    for name, id in module.networking.subnet_ids : id if can(regex("kubernetes$", name))
  ] : []

  node_groups = var.create_node_group ? {
    system = {
      subnet_ids     = local.kubernetes_subnet_ids
      instance_types = ["t3.medium"]
      desired_size   = 1
      max_size       = 2
      min_size       = 1
      labels         = { "node-role" = "system" }
    }
  } : {}
}

module "networking" {
  source = "../../../../modules/aws/networking"

  create        = var.create
  vpc_name      = var.vpc_name
  address_space = var.address_space
  subnets       = var.subnets
  environment   = "test"
  workload      = "terratest"
  region_abbv   = "usw2"

  create_internet_gateway = true
  create_nat_gateways     = true
  single_nat_gateway      = true
  enable_eks_networking   = true
  eks_cluster_name        = var.cluster_name

  tags = var.tags
}

module "eks" {
  source = "../../../../modules/aws/eks"

  create       = var.create
  cluster_name = var.cluster_name
  subnet_ids   = local.kubernetes_subnet_ids

  additional_security_group_ids = var.create ? compact([module.networking.eks_security_group_id]) : []

  kubernetes_version            = var.kubernetes_version
  endpoint_private_access       = true
  endpoint_public_access        = true
  enable_secrets_encryption     = var.enable_secrets_encryption
  bootstrap_self_managed_addons = var.bootstrap_self_managed_addons

  node_groups    = local.node_groups
  access_entries = var.access_entries
  tags           = var.tags

  depends_on = [module.networking]
}

output "cluster_id" {
  value = module.eks.cluster_id
}

output "cluster_arn" {
  value = module.eks.cluster_arn
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority" {
  value = module.eks.cluster_certificate_authority
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.eks.oidc_provider_url
}

output "node_role_arn" {
  value = module.eks.node_role_arn
}

output "node_group_names" {
  value = module.eks.node_group_names
}

output "kms_key_arn" {
  value = module.eks.kms_key_arn
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "subnet_ids" {
  value = module.networking.subnet_ids
}
