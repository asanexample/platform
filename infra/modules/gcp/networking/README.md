# GCP Networking

Creates a GCP VPC network with subnets, firewall rules, Cloud Router, and Cloud NAT. Supports GKE-specific networking (secondary IP ranges, control plane and health check firewall rules) when enabled. The module implements a cross-cloud interface contract -- variable and output names mirror the Azure networking module so that Terragrunt live configs can consume either cloud uniformly.

## Usage

```hcl
module "networking" {
  source = "../../modules/gcp/networking"

  project_id    = "my-gcp-project"
  network_name  = "vpc-platform-prod-usc1"
  environment   = "prod"
  workload      = "platform"
  region_abbv   = "usc1"
  address_space = ["10.0.0.0/16"]

  subnets = {
    "snet-platform-prod-private-usc1" = {
      address_prefixes = ["10.0.1.0/24"]
      region           = "us-central1"
      secondary_ranges = {}
    }
    "snet-platform-prod-kubernetes-usc1" = {
      address_prefixes = ["10.0.2.0/24"]
      region           = "us-central1"
      secondary_ranges = {
        "pods"     = "10.1.0.0/16"
        "services" = "10.2.0.0/20"
      }
    }
  }

  enable_gke_networking = true
  enable_cloud_nat      = true
}
```

## Examples

### Disabled Module

```hcl
module "networking" {
  source = "../../modules/gcp/networking"

  create       = false
  project_id   = "my-gcp-project"
  network_name = "vpc-platform-prod-usc1"
  environment  = "prod"
  workload     = "platform"
  region_abbv  = "usc1"
}
```

### Simple VPC Without GKE or NAT

```hcl
module "networking" {
  source = "../../modules/gcp/networking"

  project_id    = "my-gcp-project"
  network_name  = "vpc-data-dev-euw1"
  environment   = "dev"
  workload      = "data"
  region_abbv   = "euw1"
  address_space = ["10.10.0.0/16"]

  subnets = {
    "snet-data-dev-private-euw1" = {
      address_prefixes = ["10.10.1.0/24"]
      region           = "europe-west1"
      secondary_ranges = {}
    }
  }

  enable_gke_networking = false
  enable_cloud_nat      = false
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | n/a |

## Modules

No modules.

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
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g. ops, dev, staging, prod) | `string` | n/a | yes |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the VPC network to create | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project ID where resources will be created | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Short region abbreviation used in resource naming | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource names | `string` | n/a | yes |
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | Logical address space for the VPC (GCP VPCs are global; CIDRs live on subnets). Kept for cross-cloud interface parity. | `list(string)` | <pre>[<br/>  "10.0.0.0/16"<br/>]</pre> | no |
| <a name="input_cloud_nat_region"></a> [cloud\_nat\_region](#input\_cloud\_nat\_region) | Region for the Cloud Router and Cloud NAT. Defaults to the first subnet's region. | `string` | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_enable_cloud_nat"></a> [enable\_cloud\_nat](#input\_enable\_cloud\_nat) | Whether to create a Cloud Router and Cloud NAT for outbound internet access | `bool` | `true` | no |
| <a name="input_enable_gke_networking"></a> [enable\_gke\_networking](#input\_enable\_gke\_networking) | Whether to enable GKE-specific networking features | `bool` | `false` | no |
| <a name="input_gke_cluster_name"></a> [gke\_cluster\_name](#input\_gke\_cluster\_name) | Name of the GKE cluster. Used for naming related networking resources. | `string` | `null` | no |
| <a name="input_gke_pod_cidr"></a> [gke\_pod\_cidr](#input\_gke\_pod\_cidr) | Secondary IP range CIDR for GKE pods | `string` | `null` | no |
| <a name="input_gke_service_cidr"></a> [gke\_service\_cidr](#input\_gke\_service\_cidr) | Secondary IP range CIDR for GKE services | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all resources (GCP equivalent of tags) | `map(string)` | `{}` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Map of subnet names to configuration | <pre>map(object({<br/>    address_prefixes = list(string)<br/>    region           = string<br/>    secondary_ranges = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Alias for labels (cross-cloud interface compatibility). Merged with labels; labels take precedence. | `map(string)` | `{}` | no |
| <a name="input_vpc_name"></a> [vpc\_name](#input\_vpc\_name) | Alias for network\_name (cross-cloud interface compatibility) | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloud_nat_id"></a> [cloud\_nat\_id](#output\_cloud\_nat\_id) | The ID of the Cloud NAT gateway (null if Cloud NAT is disabled) |
| <a name="output_cloud_router_id"></a> [cloud\_router\_id](#output\_cloud\_router\_id) | The ID of the Cloud Router (null if Cloud NAT is disabled) |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_kubernetes_subnet_id"></a> [kubernetes\_subnet\_id](#output\_kubernetes\_subnet\_id) | The ID of the first kubernetes subnet (cross-cloud: matches Azure aks\_subnet\_id) |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The ID of the VPC network (cross-cloud: matches Azure vnet\_id) |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The name of the VPC network (cross-cloud: matches Azure vnet\_name) |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | Map of subnet names to subnet IDs |
| <a name="output_subnet_regions"></a> [subnet\_regions](#output\_subnet\_regions) | Map of subnet names to their regions |
| <a name="output_subnet_self_links"></a> [subnet\_self\_links](#output\_subnet\_self\_links) | Map of subnet names to self\_links |
| <a name="output_vpc_self_link"></a> [vpc\_self\_link](#output\_vpc\_self\_link) | The self\_link of the VPC network |
<!-- END_TF_DOCS -->

## Notes

- Firewall rules include a default-deny ingress at priority 65534 and an allow-internal rule at priority 1000 scoped to `address_space`. When `enable_gke_networking` is true, additional rules allow control plane traffic (TCP 443, 10250) and Google health check ranges.
- Cloud NAT region defaults to the first subnet's region if `cloud_nat_region` is not set. NAT uses auto-allocated IPs and covers all subnets.
- The `kubernetes_subnet_id` output automatically finds the first subnet whose name ends with `kubernetes`, providing a consistent cross-cloud interface for GKE/AKS/EKS subnet references.
- `tags` and `labels` are merged (labels take precedence) for cross-cloud compatibility -- AWS/Azure callers can pass `tags` and it maps to GCP labels.
- `vpc_name` exists as an alias for `network_name` for cross-cloud interface parity. If both are set, `network_name` takes precedence.
