# GCP Naming Module

Generates standardized, convention-aligned resource names for GCP infrastructure. Follows the same naming pattern as the Azure CAF naming module adapted for GCP resource constraints.

## Naming Pattern

- Standard resources: `{type}-{workload}-{env}-{region}`
- Tight-constraint resources (GCS, service accounts, Artifact Registry): `{type}{abbreviated_workload}{env}{region}`
- Service accounts: `sa-{abbreviated_workload}-{env}-{region}` (30 char max)

## Usage

```hcl
module "naming" {
  source = "../../modules/gcp/naming"

  workload    = "platform"
  environment = "prod"
  region_abbv = "usc1"
  project_id  = "my-gcp-project"   # optional
  unique_seed = "my-unique-seed"   # optional, used for GCS bucket uniqueness
}

resource "google_compute_network" "main" {
  name = module.naming.vpc  # "vpc-platform-prod-usc1"
}

resource "google_storage_bucket" "data" {
  name = module.naming.gcs  # "gcsplatprodusc1a1b2c3"
}

resource "google_container_cluster" "main" {
  name = module.naming.gke  # "gke-platform-prod-usc1"
}

resource "google_service_account" "app" {
  account_id = module.naming.sa  # "sa-plat-prod-usc1"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| workload | Workload identifier (2-10 chars) | string | "platform" | no |
| environment | Environment (dev, preprod, prod, test, stg, ops) | string | - | yes |
| region_abbv | Abbreviated GCP region (e.g., usc1, use1) | string | - | yes |
| project_id | Optional GCP project ID | string | null | no |
| unique_seed | Seed for globally unique names (GCS) | string | "" | no |

## Outputs

Individual outputs for each resource type (e.g., `vpc`, `gcs`, `gke`, `sa`), plus:

- `names` - Map of all generated resource names
- `resource_types` - Map of all resource type abbreviations
