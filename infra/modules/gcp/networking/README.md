# GCP Networking Module

Creates a GCP VPC network with subnets, Cloud Router, Cloud NAT, and firewall rules.

## Usage

```hcl
module "networking" {
  source = "../networking"

  create       = true
  project_id   = "platform-dev-123456"
  network_name = "vpc-platform-dev-use1"
  address_space = ["10.102.0.0/16"]
  environment  = "dev"
  workload     = "platform"
  region_abbv  = "use1"

  subnets = {
    "az1-kubernetes" = {
      address_prefixes = ["10.102.0.0/24"]
      region           = "us-east1"
      secondary_ranges = {
        pods     = "10.103.0.0/16"
        services = "10.104.0.0/20"
      }
    }
  }

  enable_gke_networking = true
  gke_cluster_name      = "gke-platform-dev-use1"
  enable_cloud_nat      = true
  cloud_nat_region      = "us-east1"

  labels = {
    environment = "dev"
    managed_by  = "terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "networking" {
  source       = "../networking"
  create       = false
  project_id   = ""
  network_name = ""
  environment  = "dev"

  workload     = "platform"
  region_abbv  = "use1"
}
```

### VPC without GKE networking

```hcl
module "networking" {
  source = "../networking"

  project_id   = "platform-dev-123456"
  network_name = "vpc-platform-dev-use1"
  address_space = ["10.102.0.0/16"]
  environment  = "dev"
  workload     = "platform"
  region_abbv  = "use1"

  subnets = {
    "az1-general" = {
      address_prefixes = ["10.102.0.0/24"]
      region           = "us-east1"
    }
  }

  labels = { environment = "dev" }
}
```

## Cross-Cloud Interface

This module exposes cloud-agnostic outputs so downstream modules can consume networking regardless of provider.

| Output | Description |
|--------|-------------|
| `network_id` | VPC network ID |
| `network_name` | VPC network name |
| `subnet_ids` | Map of subnet name to subnet ID |
| `kubernetes_subnet_id` | First subnet matching `*kubernetes` |
| `create` | Whether resources were created |

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [google_compute_firewall.allow_internal](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.deny_all_ingress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.gke_allow_health_checks](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.gke_allow_master](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_network.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_router.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router) | resource |
| [google_compute_router_nat.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_nat) | resource |
| [google_compute_subnetwork.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Environment name (e.g. ops, dev, staging, prod) | `string` | n/a | yes |
| network_name | Name of the VPC network to create | `string` | n/a | yes |
| workload | Workload name for resources | `string` | n/a | yes |
| project_id | GCP project ID where resources will be created | `string` | n/a | yes |
| region_abbv | Short region abbreviation used in resource naming | `string` | n/a | yes |
| address_space | Logical address space for the VPC (GCP VPCs are global; CIDRs live on subnets). Kept for cross-cloud interface parity. | `list(string)` | <pre>[<br/>  "10.0.0.0/16"<br/>]</pre> | no |
| cloud_nat_region | Region for the Cloud Router and Cloud NAT. Defaults to the first subnet's region. | `string` | `null` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| enable_cloud_nat | Whether to create a Cloud Router and Cloud NAT for outbound internet access | `bool` | `true` | no |
| enable_gke_networking | Whether to enable GKE-specific networking features | `bool` | `false` | no |
| gke_cluster_name | Name of the GKE cluster. Used for naming related networking resources. | `string` | `null` | no |
| gke_pod_cidr | Secondary IP range CIDR for GKE pods | `string` | `null` | no |
| gke_service_cidr | Secondary IP range CIDR for GKE services | `string` | `null` | no |
| labels | Labels to apply to all resources (GCP equivalent of tags) | `map(string)` | `{}` | no |
| subnets | Map of subnet names to configuration | <pre>map(object({<br/>    address_prefixes = list(string)<br/>    region           = string<br/>    secondary_ranges = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| tags | Alias for labels (cross-cloud interface compatibility). Merged with labels; labels take precedence. | `map(string)` | `{}` | no |
| vpc_name | Alias for network_name (cross-cloud interface compatibility) | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cloud_nat_id | The ID of the Cloud NAT gateway (null if Cloud NAT is disabled) |
| cloud_router_id | The ID of the Cloud Router (null if Cloud NAT is disabled) |
| create | Whether resources were created |
| kubernetes_subnet_id | The ID of the first kubernetes subnet (cross-cloud: matches Azure aks_subnet_id) |
| network_id | The ID of the VPC network (cross-cloud: matches Azure vnet_id) |
| network_name | The name of the VPC network (cross-cloud: matches Azure vnet_name) |
| subnet_ids | Map of subnet names to subnet IDs |
| subnet_regions | Map of subnet names to their regions |
| subnet_self_links | Map of subnet names to self_links |
| vpc_self_link | The self_link of the VPC network |
<!-- END_TF_DOCS -->

## Dependencies

None — this is a foundational networking module.

## Notes

- GCP VPCs are global and don't have a CIDR block themselves — subnets own the CIDRs. The `address_space` variable is kept for cross-cloud parity and is used in firewall `source_ranges`.
- Default firewall rules create an allow-internal rule (using `address_space`) and a deny-all-ingress rule at lowest priority.
- When `enable_gke_networking = true`, additional firewall rules allow GKE control-plane traffic (443, 10250) and Google health-check ranges.
