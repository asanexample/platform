# Region configuration for Azure eastus region

locals {
  region      = "westus"
  region_abbv = "wus"

  # Region-specific features
  region_features = {
    supports_availability_zones = true
  }

  # Common tags for this region
  region_tags = {
    Region = local.region
  }
} 