# Region configuration for Azure eastus region

locals {
  region = "eastus"
  
  # Common tags for this region
  region_tags = {
    Region = local.region
  }
} 