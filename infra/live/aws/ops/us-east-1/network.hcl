# Network configuration for AWS us-east-1 region based on allocations.csv
# VPC supernet: 10.100.0.0/16, regional block: 10.100.0.0/21

locals {
  # VPC CIDR block for us-east-1 region - from allocations.csv
  address_space = ["10.100.0.0/16"]

  # Subnet configurations for us-east-1 with three availability zones
  # Each AZ has Kubernetes, Services, Endpoints, Firewall, Transit, and Public subnets
  subnets = {
    # AZ 1 (us-east-1a) subnets
    "az1-kubernetes" = {
      address_prefixes  = ["10.100.0.0/26"]
      availability_zone = "us-east-1a"
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.100.0.64/26"]
      availability_zone = "us-east-1a"
    },
    "az1-firewall" = {
      address_prefixes  = ["10.100.0.128/26"]
      availability_zone = "us-east-1a"
    },
    "az1-services" = {
      address_prefixes  = ["10.100.0.192/27"]
      availability_zone = "us-east-1a"
    },
    "az1-public" = {
      address_prefixes  = ["10.100.0.224/28"]
      availability_zone = "us-east-1a"
      public            = true
    },
    "az1-transit" = {
      address_prefixes  = ["10.100.0.240/29"]
      availability_zone = "us-east-1a"
    },

    # AZ 2 (us-east-1b) subnets
    "az2-kubernetes" = {
      address_prefixes  = ["10.100.1.0/26"]
      availability_zone = "us-east-1b"
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.100.1.64/26"]
      availability_zone = "us-east-1b"
    },
    "az2-firewall" = {
      address_prefixes  = ["10.100.1.128/26"]
      availability_zone = "us-east-1b"
    },
    "az2-services" = {
      address_prefixes  = ["10.100.1.192/27"]
      availability_zone = "us-east-1b"
    },
    "az2-public" = {
      address_prefixes  = ["10.100.1.224/28"]
      availability_zone = "us-east-1b"
      public            = true
    },
    "az2-transit" = {
      address_prefixes  = ["10.100.1.240/29"]
      availability_zone = "us-east-1b"
    },

    # AZ 3 (us-east-1c) subnets
    "az3-kubernetes" = {
      address_prefixes  = ["10.100.2.0/26"]
      availability_zone = "us-east-1c"
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.100.2.64/26"]
      availability_zone = "us-east-1c"
    },
    "az3-firewall" = {
      address_prefixes  = ["10.100.2.128/26"]
      availability_zone = "us-east-1c"
    },
    "az3-services" = {
      address_prefixes  = ["10.100.2.192/27"]
      availability_zone = "us-east-1c"
    },
    "az3-public" = {
      address_prefixes  = ["10.100.2.224/28"]
      availability_zone = "us-east-1c"
      public            = true
    },
    "az3-transit" = {
      address_prefixes  = ["10.100.2.240/29"]
      availability_zone = "us-east-1c"
    }
  }
}
