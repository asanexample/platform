# Region configuration for Azure eastus region

locals {
  region = "eastus"
  region_abbv = "eus"
  
  # Common tags for this region
  region_tags = {
    Region = local.region
  }
} 