# Region configuration for AWS us-east-1 region

locals {
  region      = "us-east-1"
  region_abbv = "use1"

  # Region-specific features
  region_features = {
    supports_availability_zones = true
  }

  # Common tags for this region
  region_tags = {
    Region = "us-east-1"
  }
}
