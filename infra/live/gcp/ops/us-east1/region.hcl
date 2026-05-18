# Region configuration for GCP us-east1 region

locals {
  region      = "us-east1"
  region_abbv = "use1"

  # Region-specific features
  region_features = {
    supports_availability_zones = true
  }

  # Common tags/labels for this region
  region_tags = {
    region = "us-east1"
  }
}
