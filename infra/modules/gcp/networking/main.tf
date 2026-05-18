/**
 * # GCP Networking Module
 *
 * This module creates a GCP VPC network with subnets, Cloud Router, and Cloud NAT.
 * It also supports GKE-specific networking features when enabled.
 *
 * Cross-cloud interface: mirrors the Azure networking module's variable/output contract
 * so that Terragrunt live configs can treat both clouds uniformly.
 */

locals {
  # Merge tags into labels for cross-cloud compatibility (labels wins on conflict)
  effective_labels = merge(var.tags, var.labels)

  # Resolve network name (prefer network_name, fall back to vpc_name)
  effective_network_name = coalesce(var.network_name, var.vpc_name)

  # Determine NAT region: explicit override, else first subnet's region, else ""
  nat_region = coalesce(
    var.cloud_nat_region,
    try(values(var.subnets)[0].region, null),
  )

  # Identify the first kubernetes subnet for cross-cloud kubernetes_subnet_id output
  kubernetes_subnet_key = try(
    [for k, v in var.subnets : k if can(regex("kubernetes$", k))][0],
    null,
  )
}

# ---------------------------------------------------------------------------
# VPC Network
# ---------------------------------------------------------------------------
resource "google_compute_network" "this" {
  count                   = var.create ? 1 : 0
  name                    = local.effective_network_name
  auto_create_subnetworks = false
  project                 = var.project_id
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "google_compute_subnetwork" "this" {
  for_each      = var.create ? var.subnets : {}
  name          = each.key
  ip_cidr_range = each.value.address_prefixes[0]
  region        = each.value.region
  network       = google_compute_network.this[0].id
  project       = var.project_id

  dynamic "secondary_ip_range" {
    for_each = each.value.secondary_ranges
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }
}

# ---------------------------------------------------------------------------
# GKE Secondary Ranges (added to the first kubernetes subnet)
# ---------------------------------------------------------------------------
# When enable_gke_networking is true and pod/service CIDRs are provided,
# the secondary ranges are defined inline on the kubernetes subnet via the
# subnets variable's secondary_ranges field. This block is intentionally
# empty — it documents the pattern. Callers should set secondary_ranges on
# the kubernetes subnet entry in var.subnets, or pass gke_pod_cidr /
# gke_service_cidr for documentation and output purposes.

# ---------------------------------------------------------------------------
# Firewall — default deny ingress, allow internal
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  count   = var.create ? 1 : 0
  name    = "${local.effective_network_name}-allow-internal"
  network = google_compute_network.this[0].id
  project = var.project_id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = var.address_space
  priority      = 1000
}

resource "google_compute_firewall" "deny_all_ingress" {
  count   = var.create ? 1 : 0
  name    = "${local.effective_network_name}-deny-all-ingress"
  network = google_compute_network.this[0].id
  project = var.project_id

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  priority      = 65534
}

# ---------------------------------------------------------------------------
# Cloud Router
# ---------------------------------------------------------------------------
resource "google_compute_router" "this" {
  count   = var.create && var.enable_cloud_nat ? 1 : 0
  name    = "${local.effective_network_name}-router"
  region  = local.nat_region
  network = google_compute_network.this[0].id
  project = var.project_id
}

# ---------------------------------------------------------------------------
# Cloud NAT
# ---------------------------------------------------------------------------
resource "google_compute_router_nat" "this" {
  count  = var.create && var.enable_cloud_nat ? 1 : 0
  name   = "${local.effective_network_name}-nat"
  router = google_compute_router.this[0].name
  region = google_compute_router.this[0].region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  project = var.project_id

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------------------------------------------------------------------------
# GKE-specific firewall rules
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "gke_allow_master" {
  count   = var.create && var.enable_gke_networking ? 1 : 0
  name    = "${local.effective_network_name}-gke-allow-master"
  network = google_compute_network.this[0].id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["443", "10250"]
  }

  # Allow GKE control plane to reach nodes
  source_ranges = var.address_space
  priority      = 900
}

resource "google_compute_firewall" "gke_allow_health_checks" {
  count   = var.create && var.enable_gke_networking ? 1 : 0
  name    = "${local.effective_network_name}-gke-allow-health"
  network = google_compute_network.this[0].id
  project = var.project_id

  allow {
    protocol = "tcp"
  }

  # Google health check ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  priority      = 950
}
