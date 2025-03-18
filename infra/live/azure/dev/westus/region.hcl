# Region configuration for Azure westus region

locals {
  region = "westus"
  
  # Common tags for this region
  region_tags = {
    Region = local.region
  }
} 