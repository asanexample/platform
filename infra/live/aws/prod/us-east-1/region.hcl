locals {
  region      = "us-east-1"
  region_abbv = "use1"

  region_features = {
    supports_availability_zones = true
  }

  region_tags = {
    Region = "us-east-1"
  }
}
