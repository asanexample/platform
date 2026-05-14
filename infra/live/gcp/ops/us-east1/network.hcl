# Network configuration for GCP us-east1 region based on allocations.csv
# ops GCP uses 10.102.0.0/16

locals {
  # VPC logical CIDR block for us-east1 region — from allocations.csv
  address_space = ["10.102.0.0/16"]

  # Subnet configurations for us-east1 region with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, Public, and Transit subnets
  # Zone mapping: az1 → us-east1-b, az2 → us-east1-c, az3 → us-east1-d
  subnets = {
    # AZ 1 (us-east1-b) subnets
    "az1-kubernetes" = {
      address_prefixes = ["10.102.0.0/26"]
      region           = "us-east1"
    }
    "az1-services" = {
      address_prefixes = ["10.102.0.192/27"]
      region           = "us-east1"
    }
    "az1-endpoints" = {
      address_prefixes = ["10.102.0.64/26"]
      region           = "us-east1"
    }
    "az1-public" = {
      address_prefixes = ["10.102.0.224/28"]
      region           = "us-east1"
    }
    "az1-transit" = {
      address_prefixes = ["10.102.0.240/29"]
      region           = "us-east1"
    }

    # AZ 2 (us-east1-c) subnets
    "az2-kubernetes" = {
      address_prefixes = ["10.102.1.0/26"]
      region           = "us-east1"
    }
    "az2-services" = {
      address_prefixes = ["10.102.1.192/27"]
      region           = "us-east1"
    }
    "az2-endpoints" = {
      address_prefixes = ["10.102.1.64/26"]
      region           = "us-east1"
    }
    "az2-public" = {
      address_prefixes = ["10.102.1.224/28"]
      region           = "us-east1"
    }
    "az2-transit" = {
      address_prefixes = ["10.102.1.240/29"]
      region           = "us-east1"
    }

    # AZ 3 (us-east1-d) subnets
    "az3-kubernetes" = {
      address_prefixes = ["10.102.2.0/26"]
      region           = "us-east1"
    }
    "az3-services" = {
      address_prefixes = ["10.102.2.192/27"]
      region           = "us-east1"
    }
    "az3-endpoints" = {
      address_prefixes = ["10.102.2.64/26"]
      region           = "us-east1"
    }
    "az3-public" = {
      address_prefixes = ["10.102.2.224/28"]
      region           = "us-east1"
    }
    "az3-transit" = {
      address_prefixes = ["10.102.2.240/29"]
      region           = "us-east1"
    }
  }
}
