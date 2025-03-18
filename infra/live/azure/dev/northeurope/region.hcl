# Region configuration for Azure northeurope region

locals {
  region = "northeurope"
  
  # Common tags for this region
  region_tags = {
    Region = local.region
  }
} 