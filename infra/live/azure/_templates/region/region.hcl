# Region configuration for Azure [REGION_NAME] region

locals {
  region = "__REGION__"
  region_abbv = "__REGION_ABBV__"
  
  # Common tags for this region
  region_tags = {
    Region = local.region
  }
  
  # Region-specific feature flags (can be used for region capability differences)
  region_features = {
    supports_availability_zones = true   # Update based on region capabilities
  }
} 