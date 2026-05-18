# ---------------------------------------------------------------------------
# Cross-cloud interface outputs
# These outputs follow the same naming contract as the Azure networking module
# so that Terragrunt live configs can consume either cloud uniformly.
# ---------------------------------------------------------------------------

output "network_id" {
  description = "The ID of the VPC network (cross-cloud: matches Azure vnet_id)"
  value       = var.create ? google_compute_network.this[0].id : null
}

output "network_name" {
  description = "The name of the VPC network (cross-cloud: matches Azure vnet_name)"
  value       = var.create ? google_compute_network.this[0].name : null
}

output "subnet_ids" {
  description = "Map of subnet names to subnet IDs"
  value       = var.create ? { for k, v in google_compute_subnetwork.this : k => v.id } : {}
}

output "kubernetes_subnet_id" {
  description = "The ID of the first kubernetes subnet (cross-cloud: matches Azure aks_subnet_id)"
  value       = var.create && local.kubernetes_subnet_key != null ? google_compute_subnetwork.this[local.kubernetes_subnet_key].id : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}

# ---------------------------------------------------------------------------
# GCP-specific outputs
# ---------------------------------------------------------------------------

output "vpc_self_link" {
  description = "The self_link of the VPC network"
  value       = var.create ? google_compute_network.this[0].self_link : null
}

output "subnet_self_links" {
  description = "Map of subnet names to self_links"
  value       = var.create ? { for k, v in google_compute_subnetwork.this : k => v.self_link } : {}
}

output "cloud_router_id" {
  description = "The ID of the Cloud Router (null if Cloud NAT is disabled)"
  value       = var.create && var.enable_cloud_nat ? google_compute_router.this[0].id : null
}

output "cloud_nat_id" {
  description = "The ID of the Cloud NAT gateway (null if Cloud NAT is disabled)"
  value       = var.create && var.enable_cloud_nat ? google_compute_router_nat.this[0].id : null
}

output "subnet_regions" {
  description = "Map of subnet names to their regions"
  value       = var.create ? { for k, v in google_compute_subnetwork.this : k => v.region } : {}
}
