# Region configuration for Azure eastus region

locals {
  region      = "eastus"
  region_abbv = "eus"

  # Region-specific features
  region_features = {
    supports_availability_zones = true
  }

  # Common tags for this region
  region_tags = {
    Region = local.region
  }
} 