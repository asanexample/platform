# GCP Naming

Generates standardized resource names for GCP infrastructure following the pattern `{type}-{workload}-{environment}-{region}`. Handles GCP-specific naming constraints (max length, allowed characters, case rules) per resource type and automatically truncates names that exceed limits. For resources with tight character budgets (service accounts at 30 chars, GCS buckets needing global uniqueness), the module uses abbreviated workload names and compact formatting.

## Usage

```hcl
module "naming" {
  source = "../../modules/gcp/naming"

  workload    = "platform"
  environment = "prod"
  region_abbv = "usc1"
  unique_seed = "my-project-id-12345"
}

# Reference generated names:
# module.naming.vpc          => "vpc-platform-prod-usc1"
# module.naming.gke          => "gke-platform-prod-usc1"
# module.naming.gcs          => "gcsplatprodusc1a1b2c3"
# module.naming.sa           => "sa-plat-prod-usc1"
# module.naming.subnet_gke   => "snet-platform-prod-gke-usc1"
```

## Examples

### Workload with Custom Seed for Globally Unique Names

```hcl
module "naming" {
  source = "../../modules/gcp/naming"

  workload    = "data"
  environment = "dev"
  region_abbv = "euw1"
  unique_seed = "my-gcp-project-id"
}

# GCS bucket gets a 6-char hash suffix for uniqueness:
# module.naming.gcs => "gcsdatadeveuw1<6-char-md5>"
```

### Minimal Configuration

```hcl
module "naming" {
  source = "../../modules/gcp/naming"

  workload    = "hipaa"
  environment = "preprod"
  region_abbv = "use1"
}

# Without unique_seed, globally unique resources have no suffix:
# module.naming.gcs => "gcshipapreproduse1"
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment (e.g., dev, preprod, prod, ops). | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | The abbreviated GCP region name (e.g., usc1, use1, euw1). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Optional GCP project ID, used for constructing globally unique names. | `string` | `null` | no |
| <a name="input_unique_seed"></a> [unique\_seed](#input\_unique\_seed) | Seed for unique naming generation (used for globally unique resources like GCS buckets). | `string` | `""` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | The workload identifier used in resource naming (e.g., platform, data, hipaa, pci). | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudfunc"></a> [cloudfunc](#output\_cloudfunc) | Standardized name for a Cloud Function. |
| <a name="output_cloudrun"></a> [cloudrun](#output\_cloudrun) | Standardized name for a Cloud Run service. |
| <a name="output_cloudsql"></a> [cloudsql](#output\_cloudsql) | Standardized name for a Cloud SQL instance. |
| <a name="output_fw"></a> [fw](#output\_fw) | Standardized name for a firewall rule. |
| <a name="output_gce"></a> [gce](#output\_gce) | Standardized name for a Compute Engine instance. |
| <a name="output_gcr"></a> [gcr](#output\_gcr) | Standardized name for an Artifact Registry repository. |
| <a name="output_gcs"></a> [gcs](#output\_gcs) | Standardized name for a Cloud Storage bucket (globally unique, lowercase). |
| <a name="output_gke"></a> [gke](#output\_gke) | Standardized name for a GKE cluster. |
| <a name="output_kms_key"></a> [kms\_key](#output\_kms\_key) | Standardized name for a KMS key. |
| <a name="output_kms_keyring"></a> [kms\_keyring](#output\_kms\_keyring) | Standardized name for a KMS key ring. |
| <a name="output_lb"></a> [lb](#output\_lb) | Standardized name for a load balancer. |
| <a name="output_memorystore"></a> [memorystore](#output\_memorystore) | Standardized name for a Memorystore instance. |
| <a name="output_names"></a> [names](#output\_names) | Map of all generated resource names. |
| <a name="output_nat"></a> [nat](#output\_nat) | Standardized name for a Cloud NAT. |
| <a name="output_pubsub_sub"></a> [pubsub\_sub](#output\_pubsub\_sub) | Standardized name for a Pub/Sub subscription. |
| <a name="output_pubsub_topic"></a> [pubsub\_topic](#output\_pubsub\_topic) | Standardized name for a Pub/Sub topic. |
| <a name="output_resource_types"></a> [resource\_types](#output\_resource\_types) | All resource type abbreviations. |
| <a name="output_router"></a> [router](#output\_router) | Standardized name for a Cloud Router. |
| <a name="output_sa"></a> [sa](#output\_sa) | Standardized name for a service account (30 char max, lowercase). |
| <a name="output_subnet"></a> [subnet](#output\_subnet) | Base subnet name for generating type-specific subnet names. |
| <a name="output_subnet_data"></a> [subnet\_data](#output\_subnet\_data) | Standardized name for a data subnet. |
| <a name="output_subnet_gke"></a> [subnet\_gke](#output\_subnet\_gke) | Standardized name for a GKE subnet. |
| <a name="output_subnet_private"></a> [subnet\_private](#output\_subnet\_private) | Standardized name for a private subnet. |
| <a name="output_subnet_proxy"></a> [subnet\_proxy](#output\_subnet\_proxy) | Standardized name for a proxy-only subnet. |
| <a name="output_subnet_public"></a> [subnet\_public](#output\_subnet\_public) | Standardized name for a public subnet. |
| <a name="output_vpc"></a> [vpc](#output\_vpc) | Standardized name for a GCP VPC network. |
<!-- END_TF_DOCS -->

## Notes

- Workload abbreviations are defined in `main.tf` for known workloads (platform -> plat, connectivity -> conn, etc.). Unknown workloads are truncated to 4 characters.
- Service account names have a strict 30-character limit in GCP, so they always use the abbreviated workload form.
- The `unique_seed` variable produces a 6-character MD5 hash suffix appended to globally unique resources (GCS buckets). Without it, bucket names may collide across projects.
- Subnet helpers (`subnet_public`, `subnet_private`, `subnet_data`, `subnet_gke`, `subnet_proxy`) are generated independently from the main `names` map and follow a `{type}-{workload}-{env}-{purpose}-{region}` pattern.
- Valid environments are restricted to: dev, preprod, prod, test, stg, ops.
